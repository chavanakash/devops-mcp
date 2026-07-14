# Architecture

This repo is both a portfolio site and the infrastructure that runs it. Every
layer is real: a local Kubernetes cluster, GitOps deployments via Argo CD, CI/CD
with code scanning, and Claude actively watching and healing the cluster through
the Model Context Protocol (MCP) — not just monitoring it.

```
                          ┌───────────────────────────────┐
   PR / push to main ───▶ │  GitHub Actions                │
                          │  - CodeQL + Trivy code scan     │
                          │  - status-api build → ghcr.io   │
                          │  - site build → GitHub Pages    │
                          └──────────────┬───────────────────┘
                                          │ GITHUB_TOKEN (no long-lived secrets)
                                          ▼
   ┌────────────────────────────────────────────────────────────────┐
   │ Docker Desktop — local Kubernetes                                │
   │                                                                   │
   │  Argo CD (full install)  watches k8s/ on this repo, auto-syncs   │
   │    └─ status-api          live-infra widget backend               │
   │                            LoadBalancer → localhost → ngrok        │
   │  Datadog Agent (opt-in)  ships host/pod metrics                   │
   └────────────────────────────────────────────────────────────────┘
                    │                                    │
        ngrok tunnel (public,                  Datadog/PagerDuty/Slack
        while running)                              (opt-in)
                    ▼                                    ▼
   ┌─────────────────────────┐            ┌───────────────────────┐
   │ GitHub Pages             │            │ Claude Code + 7 MCPs   │
   │ portfolio (always up)    │            │ (.mcp.json) —          │
   │ "Live infra" widget calls│            │ includes an active      │
   │ the ngrok URL            │            │ self-heal loop          │
   └─────────────────────────┘            └───────────────────────┘
```

## Design decisions & why

- **Local Kubernetes, not cloud.** An earlier version of this project ran k3s +
  Argo CD on a free-tier AWS t3.micro (1GiB RAM). It worked, but only after a
  long chain of fixes (CRD apply size limits, resource exhaustion, a systemd
  race, missing ECR pull credentials) — and even the maximally-trimmed "core"
  Argo CD still swap-thrashed under real load (`vmstat` showed 70-97% iowait).
  All of that AWS infrastructure was destroyed. Docker Desktop's Kubernetes on
  a real machine has none of those constraints — the **full** Argo CD install
  (API server, UI, everything) runs cleanly here, no trimming needed.
- **GitHub Pages + ngrok, not one hosting story.** GitHub Pages serves the
  static portfolio for free, forever, always up — good for a link on a resume.
  The Kubernetes/Argo CD/self-heal story is the actually interesting part of
  this project, but it only runs on a personal machine — being honest about
  that (an ngrok tunnel, up only while the Mac + tunnel are running) beats
  pretending it's a 24/7 cloud service it isn't. The "Live infra" widget's
  "unreachable" state *is* the honest state most of the time.
- **ghcr.io, not a cloud registry.** Free, and GitHub Actions pushes to it with
  the built-in `GITHUB_TOKEN` — no OIDC role, no long-lived cloud credentials
  to manage. The cluster pulls via a manually-created `imagePullSecret` backed
  by a GitHub PAT (`read:packages`) — unlike the old ECR tokens, these don't
  expire every 12 hours, so no refresh automation is needed.
- **`LoadBalancer` Services, not NodePort.** Docker Desktop's Kubernetes
  auto-binds `LoadBalancer` Services to `localhost` — simpler than the
  NodePort + `kubectl port-forward` dance the AWS version needed.
- **Self-healing is an active Claude loop, not just k8s's own restarts.**
  Kubernetes already restarts crashed pods via liveness probes — that's not
  novel. What this project adds is `runbooks/self-heal.md`: a concrete
  diagnose-then-remediate playbook (different actions for CrashLoopBackOff vs.
  ImagePullBackOff vs. OOMKilled vs. a stuck Argo CD sync) that Claude follows
  when invoked via `/loop 5m` against the Kubernetes MCP. Worth being precise
  about its limits: this runs only while that Claude Code session is open on
  your machine — it's not an unattended daemon, and doesn't pretend to be one.
- **Code scanning as a real CI gate.** `code-scan.yml` runs CodeQL (SAST, on
  every push/PR + weekly) and a Trivy filesystem scan; `status-api-ci.yml`
  additionally Trivy-scans the *built image* and fails the build on
  CRITICAL/HIGH vulnerabilities before it's ever pushed.

## The MCPs

Claude's project-level MCP config (`.mcp.json`) wires up seven servers, across
the "MCP Stack Map" categories — Infra, Observability, CI/CD, Comms & Response.
Package names below were verified against each project's own docs/repo, not
guessed — worth re-checking for updates before first use, since this ecosystem
moves fast.

| # | MCP | Package / endpoint | What it's for here |
|---|---|---|---|
| 1 | Kubernetes | [`mcp-server-kubernetes`](https://github.com/Flux159/mcp-server-kubernetes) (npm) | Inspects pods/events/logs on the local cluster — the backbone of the self-heal loop (`runbooks/self-heal.md`) |
| 2 | Argo CD | [`argocd-mcp`](https://github.com/argoproj-labs/mcp-for-argocd) (npm, Akuity) | Audits sync status, drift, and application health for `status-api` — has a real API to talk to now that Argo CD runs full-install locally |
| 3 | GitHub | [`github-mcp-server`](https://github.com/github/github-mcp-server) (Docker, official) | Reviews PRs, opens issues, inspects Actions runs and code-scan results |
| 4 | Datadog | [Datadog's hosted MCP server](https://docs.datadoghq.com/bits_ai/mcp_server/) (remote HTTP) | Reads dashboards/monitors (opt-in) |
| 5 | PagerDuty | [`pagerduty-mcp-server`](https://github.com/PagerDuty/pagerduty-mcp-server) (PyPI/uvx, official) | Checks incidents, on-call state, escalation policy (opt-in) |
| 6 | Slack | [`@modelcontextprotocol/server-slack`](https://www.npmjs.com/package/@modelcontextprotocol/server-slack) (npm, official reference) | Posts deploy/incident updates, reads thread context |
| 7 | Incident Runbook | [`@modelcontextprotocol/server-filesystem`](https://www.npmjs.com/package/@modelcontextprotocol/server-filesystem) (npm, official, read-only) | Serves `runbooks/*.md` directly into the conversation |

### Turning on the self-heal loop

```
/loop 5m Follow runbooks/self-heal.md against the local cluster via the Kubernetes MCP.
```

Claude checks pod and Argo CD Application health every 5 minutes, diagnoses
anything unhealthy before acting, and follows the specific remediation for each
failure mode in the runbook — reporting "all healthy" and staying quiet when
there's nothing to do.

### Other example prompts

- *"Is `status-api` actually synced right now?"* → Argo CD MCP.
- *"Something's wrong with the cluster — what happened?"* → Kubernetes MCP
  reads events/logs, Incident Runbook MCP surfaces the matching SOP.
- *"Did the last push pass code scanning?"* → GitHub MCP checks the `code scan`
  workflow run and any new Security tab findings.

## Repo layout

```
site/               Astro portfolio website (GitHub Pages)
apps/status-api/    small service powering the site's "live infra" widget
k8s/                Argo CD Application manifests + status-api / datadog-agent Kustomize bases
scripts/            local cluster bootstrap (installs Argo CD, creates Applications)
runbooks/           incident SOPs + the self-heal playbook (source for the Incident Runbook MCP)
.github/workflows/  CI/CD (code scan, image build → ghcr.io, site deploy → Pages)
.mcp.json           Claude Code MCP server registrations
SETUP.md            one-time checklist: accounts, secrets, and manual steps
```
