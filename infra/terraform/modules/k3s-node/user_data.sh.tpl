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

# Argo CD (full install — API server + UI, not the headless "core" profile — so it's
# usable for demos/screenshots). Reachable only via `aws ssm start-session` port
# forwarding, never exposed publicly.
/usr/local/bin/k3s kubectl create namespace argocd --dry-run=client -o yaml | /usr/local/bin/k3s kubectl apply -f -
# --server-side: Argo CD's applicationsets.argoproj.io CRD is large enough that
# client-side `kubectl apply`'s last-applied-configuration annotation exceeds the
# API server's 262144-byte annotation limit. Server-side apply doesn't use that
# annotation at all, which is the standard workaround for this.
/usr/local/bin/k3s kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Trim to what we actually use: application-controller (syncs Applications),
# repo-server (renders manifests), redis (their cache), and server (API+UI).
# Dex (SSO — we don't use Argo CD logins beyond the local `claude`/admin
# accounts), notifications-controller (we notify via GitHub Actions -> Slack
# instead), and applicationset-controller (we only use plain Applications, not
# ApplicationSets) are pure overhead on a 1GiB node — scale them to zero rather
# than leave three extra components competing for the same RAM.
/usr/local/bin/k3s kubectl -n argocd scale deployment argocd-dex-server argocd-notifications-controller argocd-applicationset-controller --replicas=0

# A dedicated read-only "claude" account, rather than handing the Kubernetes/AWS/
# GitHub/PagerDuty MCP pattern's least-privilege habit an admin token here too.
# It can view app/sync status but not trigger syncs or edit anything — matches
# the "MCPs observe, humans (or Argo CD's own automation) act" split in
# ARCHITECTURE.md. See runbooks/argocd-access.md for generating its token.
# Applied before the resource-limit patch below (not via a separate `rollout
# restart` afterwards) so argocd-server only rolls over once, not twice — two
# sequential rollouts on an already resource-tight node left old and new pods
# stuck competing with each other instead of either one settling.
/usr/local/bin/k3s kubectl -n argocd patch configmap argocd-cm --type merge \
  -p '{"data":{"accounts.claude":"apiKey"}}'
/usr/local/bin/k3s kubectl -n argocd patch configmap argocd-rbac-cm --type merge \
  -p '{"data":{"policy.csv":"p, role:claude-readonly, applications, get, */*, allow\ng, claude, role:claude-readonly\n"}}'

# Conservative resource ceilings on what's left, so no single component can
# balloon and tip the node back into swap-thrashing the way the unbounded
# defaults did. This is also what picks up the ConfigMap changes above, since
# it's the one thing here that actually restarts argocd-server.
/usr/local/bin/k3s kubectl -n argocd set resources deployment/argocd-server --requests=cpu=25m,memory=64Mi --limits=cpu=150m,memory=160Mi
/usr/local/bin/k3s kubectl -n argocd set resources deployment/argocd-repo-server --requests=cpu=50m,memory=128Mi --limits=cpu=200m,memory=256Mi
/usr/local/bin/k3s kubectl -n argocd set resources deployment/argocd-redis --requests=cpu=10m,memory=32Mi --limits=cpu=100m,memory=64Mi
/usr/local/bin/k3s kubectl -n argocd set resources statefulset/argocd-application-controller --requests=cpu=50m,memory=128Mi --limits=cpu=200m,memory=256Mi

# Expose the Argo CD API/UI on a fixed NodePort. This is *not* opened in the
# security group (nothing but status-api is) — it's reached the same way as
# kubectl, via `aws ssm start-session ... AWS-StartPortForwardingSession`, which
# tunnels through the SSM agent rather than the network, so it never needs an
# inbound SG rule. See runbooks/argocd-access.md.
#
# Not gated on a `kubectl wait` for argocd-server's readiness: none of the
# remaining steps (this patch, or applying the Application CRs below) actually
# talk to the argocd-server pod — they're all just objects written to the k3s
# API server, which reconciles them once argocd-server (and
# application-controller, which is what really matters for GitOps syncing)
# comes up on its own. A hard wait here previously timed out under resource
# pressure and aborted the whole script before any of this ran.
/usr/local/bin/k3s kubectl -n argocd patch svc argocd-server -p '{"spec": {"type": "NodePort", "ports": [{"name": "https", "port": 443, "targetPort": 8080, "nodePort": 30444}]}}'

# Root Application: tells Argo CD to track k8s/status-api on the portfolio repo and
# keep the cluster's state in sync with it (GitOps).
cat <<EOF | /usr/local/bin/k3s kubectl apply -f -
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

%{ if deploy_datadog_agent ~}
# Second Application: the Datadog Agent DaemonSet. It will sit in CrashLoopBackOff
# until the `datadog-secret` Secret is created in the `datadog` namespace (a manual,
# one-time step documented in runbooks/ — the API key is never committed to git).
# Argo CD's selfHeal picks it up automatically once the secret exists.
cat <<EOF | /usr/local/bin/k3s kubectl apply -f -
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
%{ endif ~}
