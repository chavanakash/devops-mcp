# Setup checklist

The local cluster is already bootstrapped (Argo CD installed and running on
Docker Desktop's Kubernetes via `scripts/setup-local-cluster.sh`). What's left is
pushing the code, the one-time manual steps only you can do (GitHub Pages
toggle, ghcr pull secret, ngrok), and wiring Claude up.

## 1. Push the code

```bash
git add -A
git commit -m "Pivot to local Kubernetes + Argo CD + AI self-healing"
git push
```

## 2. Enable GitHub Pages

Repo → **Settings → Pages → Source: GitHub Actions**. One-time toggle;
`site-deploy.yml` handles the rest on every push to `site/`.

## 3. ghcr.io pull secret (cluster-side, one-time)

See [runbooks/local-cluster-access.md](./runbooks/local-cluster-access.md) §3 —
a classic GitHub PAT (`read:packages` scope) turned into a
`kubectl create secret docker-registry` command. `status-api`'s Deployment
already references it via `imagePullSecrets`.

## 4. First status-api image

`status-api-ci.yml` builds and pushes on changes to `apps/status-api/**` — push
already covers this from step 1 if that path was touched. Otherwise, trigger it
manually: repo → **Actions → status-api CI → Run workflow**.

Once it's pushed, Argo CD (already watching `k8s/status-api` on `main`) syncs
automatically. Confirm:

```bash
kubectl config use-context docker-desktop
kubectl get applications -n argocd
kubectl get pods -n default
```

## 5. Public tunnel for the "Live infra" widget

```bash
kubectl get svc status-api -n default   # note the port
ngrok http <port>
```

Take the printed `https://*.ngrok-free.app` URL and set it as the
`STATUS_API_URL` repo variable (**Settings → Secrets and variables → Actions →
Variables**), then re-run `deploy site` (or push any `site/` change) to rebuild
with it baked in. See
[runbooks/local-cluster-access.md](./runbooks/local-cluster-access.md) §4 —
this needs redoing every time you restart `ngrok` without a reserved static
domain, since the URL changes.

## 6. Optional: Datadog / PagerDuty / Slack

All opt-in, all deferred by default:

- **Datadog**: [runbooks/datadog-agent-setup.md](./runbooks/datadog-agent-setup.md)
- **PagerDuty / Slack**: create the accounts/webhook, export
  `PAGERDUTY_API_TOKEN`, `SLACK_BOT_TOKEN`, `SLACK_TEAM_ID` for step 7 below,
  and add `SLACK_WEBHOOK_URL` as a repo secret if you want deploy notifications
  in `status-api-ci.yml`/`site-deploy.yml`.

## 7. Wire Claude up

```bash
export KUBECONFIG=~/.kube/config   # or wherever yours lives; docker-desktop context
export ARGOCD_BASE_URL=https://localhost ARGOCD_API_TOKEN=...   # runbooks/local-cluster-access.md §2
export GITHUB_PERSONAL_ACCESS_TOKEN=...
export SLACK_BOT_TOKEN=... SLACK_TEAM_ID=...
export DD_API_KEY=... DD_APP_KEY=...            # only if Datadog is set up
export PAGERDUTY_API_TOKEN=...                  # only if PagerDuty is set up
claude mcp list   # should show all 7 servers from .mcp.json connected
```

## 8. Turn on self-healing

```
/loop 5m Follow runbooks/self-heal.md against the local cluster via the Kubernetes MCP.
```

Runs for as long as that Claude Code session stays open — see
[ARCHITECTURE.md](./ARCHITECTURE.md) for why this is an active session loop,
not an unattended daemon.

## 9. Fill in real content

- `site/src/components/About.astro`, `Hero.astro`, `Projects.astro`, `Footer.astro`
  — swap placeholder bio/links for the real thing.
