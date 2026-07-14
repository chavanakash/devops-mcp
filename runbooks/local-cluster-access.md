# Local cluster access: Argo CD, ghcr pull secret, ngrok tunnel

Everything here runs on Docker Desktop's local Kubernetes — no cloud, no SSH,
no tunnels needed just to reach the cluster itself.

## 0. kubectl context

```bash
kubectl config use-context docker-desktop
kubectl get nodes   # should show one node, Ready
```

This is the `KUBECONFIG`/context the Kubernetes MCP in `.mcp.json` uses too —
nothing extra to configure, it reads your default kubeconfig.

## 1. Argo CD UI

`scripts/setup-local-cluster.sh` already exposed `argocd-server` via a
`LoadBalancer` service, which Docker Desktop auto-binds to `localhost`:

```bash
kubectl get svc argocd-server -n argocd   # EXTERNAL-IP should read "localhost"
```

Open **https://localhost** (accept the self-signed cert warning). Log in as
`admin` with the password the setup script printed (or re-fetch it):

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

Change it after first login (`argocd account update-password`, or via the UI).

## 2. Token for the Argo CD MCP

With the `argocd` CLI (`brew install argocd`) logged in as admin:

```bash
argocd login localhost --insecure
argocd account generate-token
```

Set that as `ARGOCD_API_TOKEN` and `ARGOCD_BASE_URL=https://localhost` wherever
you run `claude` with this repo's `.mcp.json`.

## 3. ghcr.io pull secret (one-time, manual)

`status-api`'s package is private, so the cluster needs credentials to pull it.
Create a classic GitHub PAT with the `read:packages` scope
(https://github.com/settings/tokens), then:

```bash
kubectl create secret docker-registry ghcr-pull-secret \
  --namespace=default \
  --docker-server=ghcr.io \
  --docker-username=<your-github-username> \
  --docker-password=<the-PAT> \
  --dry-run=client -o yaml | kubectl apply -f -
```

Unlike the ECR tokens from the previous AWS-based version of this project,
GitHub PATs don't expire every 12 hours — no refresh automation needed. Just
redo this if you ever revoke/rotate the token.

## 4. Public tunnel (ngrok) for status-api

The portfolio's "Live infra" widget on GitHub Pages needs a real public URL to
call — GitHub Pages can't proxy to `localhost` the way the old CloudFront setup
could. `status-api` is exposed locally the same way as Argo CD, via a
`LoadBalancer` service bound to `localhost`:

```bash
kubectl get svc status-api -n default   # note the port
ngrok http <port>
```

`ngrok` prints a public HTTPS URL (e.g. `https://abcd1234.ngrok-free.app`) —
this changes every time you restart `ngrok` unless you've reserved a static
domain on your ngrok account. Whenever it changes:

1. Update the `STATUS_API_URL` repository variable (Settings → Secrets and
   variables → Actions → Variables) to the new ngrok URL.
2. Re-run the `deploy site` GitHub Actions workflow (or push any change to
   `site/`) to rebuild with the new `PUBLIC_STATUS_API_URL` baked in.

This means the "Live infra" widget is only genuinely reachable while your Mac
is on, Docker Desktop's Kubernetes is running, and `ngrok` is tunneling — which
is exactly what the widget's own "unreachable" fallback state communicates when
it's not.
