#!/bin/bash
set -euxo pipefail

# t3.micro has 1GiB RAM; k3s + Argo CD is tight without a bit of headroom.
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# k3s: single-node, no Traefik (we expose status-api directly via NodePort, no
# ingress/domain in play), kubeconfig world-readable so the ubuntu user / SSM
# sessions can use kubectl without extra sudo dancing.
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_EXEC="--disable traefik --write-kubeconfig-mode 644" sh -

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

until /usr/local/bin/k3s kubectl get nodes >/dev/null 2>&1; do
  sleep 5
done

# Argo CD (full install — API server + UI, not the headless "core" profile — so it's
# usable for demos/screenshots). Reachable only via `aws ssm start-session` port
# forwarding, never exposed publicly.
/usr/local/bin/k3s kubectl create namespace argocd --dry-run=client -o yaml | /usr/local/bin/k3s kubectl apply -f -
/usr/local/bin/k3s kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Expose the Argo CD API/UI on a fixed NodePort. This is *not* opened in the
# security group (nothing but status-api is) — it's reached the same way as
# kubectl, via `aws ssm start-session ... AWS-StartPortForwardingSession`, which
# tunnels through the SSM agent rather than the network, so it never needs an
# inbound SG rule. See runbooks/argocd-access.md.
/usr/local/bin/k3s kubectl -n argocd wait --for=condition=available --timeout=300s deployment/argocd-server
/usr/local/bin/k3s kubectl -n argocd patch svc argocd-server -p '{"spec": {"type": "NodePort", "ports": [{"name": "https", "port": 443, "targetPort": 8080, "nodePort": 30444}]}}'

# A dedicated read-only "claude" account, rather than handing the Kubernetes/AWS/
# GitHub/PagerDuty MCP pattern's least-privilege habit an admin token here too.
# It can view app/sync status but not trigger syncs or edit anything — matches
# the "MCPs observe, humans (or Argo CD's own automation) act" split in
# ARCHITECTURE.md. See runbooks/argocd-access.md for generating its token.
/usr/local/bin/k3s kubectl -n argocd patch configmap argocd-cm --type merge \
  -p '{"data":{"accounts.claude":"apiKey"}}'
/usr/local/bin/k3s kubectl -n argocd patch configmap argocd-rbac-cm --type merge \
  -p '{"data":{"policy.csv":"p, role:claude-readonly, applications, get, */*, allow\ng, claude, role:claude-readonly\n"}}'
/usr/local/bin/k3s kubectl -n argocd rollout restart deployment argocd-server

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
