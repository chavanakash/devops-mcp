#!/bin/bash
# Bootstraps Argo CD on Docker Desktop's local Kubernetes and points it at this
# repo's k8s/status-api Application. Idempotent — safe to re-run.
#
# Replaces what used to be a Terraform-driven EC2 user-data script: there's no
# cloud instance to provision anymore, just a local cluster to configure.
set -euo pipefail

GITHUB_REPO="${GITHUB_REPO:-chavanakash/devops-mcp}"
DEPLOY_DATADOG_AGENT="${DEPLOY_DATADOG_AGENT:-false}"

CTX="$(kubectl config current-context)"
if [ "$CTX" != "docker-desktop" ]; then
  echo "Current kubectl context is '$CTX', not 'docker-desktop'."
  echo "Run: kubectl config use-context docker-desktop"
  exit 1
fi

echo "== namespace =="
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo "== Argo CD (full install — real resources here, no trimming needed) =="
# --server-side: the applicationsets.argoproj.io CRD is large enough that
# client-side apply's last-applied-configuration annotation exceeds the API
# server's 262144-byte limit (bit us running this on AWS; same fix applies).
kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "== waiting for argocd-server =="
kubectl -n argocd wait --for=condition=available --timeout=300s deployment/argocd-server

echo "== exposing argocd-server via LoadBalancer (Docker Desktop binds this to localhost) =="
kubectl -n argocd patch svc argocd-server -p '{"spec": {"type": "LoadBalancer"}}'

echo "== status-api Application =="
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: status-api
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/${GITHUB_REPO}.git
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

if [ "$DEPLOY_DATADOG_AGENT" = "true" ]; then
  echo "== datadog-agent Application =="
  cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: datadog-agent
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/${GITHUB_REPO}.git
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
fi

echo ""
echo "== done =="
echo "Initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
echo ""
echo "Argo CD UI: run 'kubectl get svc argocd-server -n argocd' for the LoadBalancer address"
echo "(usually https://localhost:443 — accept the self-signed cert warning)."
echo "See runbooks/local-cluster-access.md for the rest (imagePullSecret, ngrok, MCP token)."
