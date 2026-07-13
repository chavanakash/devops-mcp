#!/bin/bash
set -euxo pipefail

# t3.micro has 1GiB RAM; k3s + Argo CD is tight without real headroom.
if [ ! -f /swapfile ]; then
  fallocate -l 3G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# k3s: single-node, no Traefik (we expose status-api directly via NodePort, no
# ingress/domain in play) and no bundled metrics-server (not needed — nothing
# here uses `kubectl top` or HPA — and it was one more thing competing for the
# same 1GiB). kubeconfig world-readable so the ubuntu user / SSM sessions can
# use kubectl without extra sudo dancing.
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_EXEC="--disable traefik --disable metrics-server --write-kubeconfig-mode 644" sh -

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

until /usr/local/bin/k3s kubectl get nodes >/dev/null 2>&1; do
  sleep 5
done

# A 1-vCPU box applying/patching dozens of objects against its own API server
# hits transient `Error from server (Timeout)` responses under load — not a
# real failure, just the API server momentarily behind. Retry instead of
# letting one blip (via `set -e`) abort everything that hasn't run yet.
k() {
  local n=0 max=6
  until /usr/local/bin/k3s kubectl "$@"; do
    n=$((n + 1))
    [ "$n" -ge "$max" ] && return 1
    sleep 15
  done
}

# ECR pull credentials: unlike EKS's kubelet, plain k3s/containerd has no
# built-in AWS SigV4 support for pulling from private ECR repos. Mint a token
# via the node's IAM role (AmazonEC2ContainerRegistryReadOnly, attached above)
# and hand it to the cluster as a Secret that status-api's imagePullSecrets
# references. ECR tokens expire every 12h, so a systemd timer keeps it fresh.
apt-get update -y
apt-get install -y awscli

cat > /usr/local/bin/ecr-cred-refresh.sh <<SCRIPT
#!/bin/bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
PASSWORD=\$(/usr/bin/aws ecr get-login-password --region ${aws_region})
/usr/local/bin/k3s kubectl create secret docker-registry ecr-pull-secret \
  --docker-server=${ecr_registry} \
  --docker-username=AWS \
  --docker-password="\$PASSWORD" \
  --namespace=default \
  --dry-run=client -o yaml | /usr/local/bin/k3s kubectl apply -f -
SCRIPT
chmod +x /usr/local/bin/ecr-cred-refresh.sh

cat > /etc/systemd/system/ecr-cred-refresh.service <<'EOF'
[Unit]
Description=Refresh the ECR pull secret for k3s
[Service]
Type=oneshot
ExecStart=/usr/local/bin/ecr-cred-refresh.sh
EOF

cat > /etc/systemd/system/ecr-cred-refresh.timer <<'EOF'
[Unit]
Description=Run ecr-cred-refresh every 6 hours
[Timer]
# Comfortably past cloud-init's own runtime (it installs awscli's dependency
# tree — ImageMagick, Ghostscript, etc. — which alone can take a minute or
# more), so this never races the explicit call below over creating the same
# not-yet-existing secret. kubectl apply's create-or-update logic isn't
# atomic: two concurrent first-time applies of the same object can both see
# "not found" and both try to create it, and the loser gets an AlreadyExists
# error. This bit us at OnBootSec=1min.
OnBootSec=15min
OnUnitActiveSec=6h
[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable ecr-cred-refresh.timer
systemctl start ecr-cred-refresh.timer
/usr/local/bin/ecr-cred-refresh.sh

# Argo CD "core" install: application-controller + repo-server + redis (+
# applicationset-controller, scaled to 0 below) only — no API server, no UI, no
# Dex, no notifications-controller. The full install's argocd-server alone was
# enough extra RAM demand to tip this 1GiB node into sustained swap-thrashing
# (measured: 70-97% iowait, confirmed via vmstat) even after every other trim
# and resource cap; core mode is the only thing that actually fixed it, at the
# cost of no Argo CD web UI/REST API — Application sync/health status is read
# via the Kubernetes MCP (`kubectl get applications -n argocd`) instead of a
# dedicated Argo CD MCP. See runbooks/argocd-access.md.
/usr/local/bin/k3s kubectl create namespace argocd --dry-run=client -o yaml > /tmp/argocd-ns.yaml
k apply -f /tmp/argocd-ns.yaml
# --server-side: Argo CD's applicationsets.argoproj.io CRD is large enough that
# client-side `kubectl apply`'s last-applied-configuration annotation exceeds the
# API server's 262144-byte annotation limit. Server-side apply doesn't use that
# annotation at all, which is the standard workaround for this.
k apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/core-install.yaml

# The full install's argocd-server auto-creates a "default" AppProject at
# startup; core mode has no API server to run that logic, so Applications
# referencing project "default" (ours do) fail with InvalidSpecError until
# one exists. Create it explicitly.
cat > /tmp/default-appproject.yaml <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: default
  namespace: argocd
spec:
  description: Default permissive project (core mode has no API server to auto-create this)
  sourceRepos:
    - '*'
  destinations:
    - namespace: '*'
      server: '*'
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'
EOF
k apply -f /tmp/default-appproject.yaml

# We only use plain Applications, not ApplicationSets — one less component
# competing for RAM.
k -n argocd scale deployment argocd-applicationset-controller --replicas=0

# Conservative resource ceilings on what's left, so no single component can
# balloon and tip the node back into swap-thrashing.
k -n argocd set resources deployment/argocd-repo-server --requests=cpu=50m,memory=128Mi --limits=cpu=200m,memory=256Mi
k -n argocd set resources deployment/argocd-redis --requests=cpu=10m,memory=32Mi --limits=cpu=100m,memory=64Mi
k -n argocd set resources statefulset/argocd-application-controller --requests=cpu=50m,memory=128Mi --limits=cpu=200m,memory=256Mi

# Root Application: tells Argo CD to track k8s/status-api on the portfolio repo and
# keep the cluster's state in sync with it (GitOps).
cat > /tmp/status-api-app.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: status-api
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/${github_repo}.git
    targetRevision: main
    path: k8s/status-api
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
k apply -f /tmp/status-api-app.yaml

%{ if deploy_datadog_agent ~}
# Second Application: the Datadog Agent DaemonSet. It will sit in CrashLoopBackOff
# until the `datadog-secret` Secret is created in the `datadog` namespace (a manual,
# one-time step documented in runbooks/ — the API key is never committed to git).
# Argo CD's selfHeal picks it up automatically once the secret exists.
cat > /tmp/datadog-agent-app.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: datadog-agent
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/${github_repo}.git
    targetRevision: main
    path: k8s/datadog-agent
  destination:
    server: https://kubernetes.default.svc
    namespace: datadog
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
k apply -f /tmp/datadog-agent-app.yaml
%{ endif ~}
