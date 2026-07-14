# DevOps Portfolio — Claude-Managed AI SRE Stack

A personal DevOps portfolio: a real portfolio website, backed by a real local
Kubernetes + Argo CD GitOps deployment, where the infrastructure itself is
inspected and operated through Claude using the Model Context Protocol (MCP) —
including AI-driven self-healing, not just monitoring.

> Status: 🚧 work in progress. See [ARCHITECTURE.md](./ARCHITECTURE.md) for the full
> design, or [SETUP.md](./SETUP.md) for the one-time deployment checklist.

## Live

- Portfolio: **https://chavanakash.github.io/devops-mcp/** (GitHub Pages, always up)
- Live infra demo widget: pulled from a `status-api` service running on Docker
  Desktop's local Kubernetes, deployed via Argo CD GitOps, reachable through an
  ngrok tunnel — up whenever the local cluster + tunnel are running, not a 24/7
  cloud endpoint. See [ARCHITECTURE.md](./ARCHITECTURE.md) for why.

## What this project demonstrates

| Layer | Tooling |
|---|---|
| Frontend | Astro portfolio site, deployed to GitHub Pages |
| Compute | Docker Desktop's local Kubernetes |
| CI/CD | GitHub Actions — CodeQL + Trivy code scanning, Docker build/push to ghcr.io, GitOps via Argo CD |
| AI operations | Claude Code driving all of the above through 7 MCP servers, including an active self-heal loop over the Kubernetes MCP |
| Observability | Datadog dashboards/monitors as code (opt-in) |
| Incident response | PagerDuty escalation policies + Slack notifications + markdown runbooks (opt-in) |

## Repo layout

```
site/               Astro portfolio website
apps/status-api/    small service powering the site's "live infra" widget
k8s/                Argo CD + status-api Kubernetes manifests
scripts/            local cluster bootstrap (Argo CD install)
runbooks/           incident SOPs, including the self-heal playbook (source for the Incident Runbook MCP)
.github/workflows/  CI/CD (code scan, image build, site deploy)
.mcp.json           Claude Code MCP server registrations
SETUP.md            one-time deployment checklist
```

## Running Claude against this infra

This repo ships a project-level `.mcp.json` registering MCP servers for
Kubernetes, Argo CD, Datadog, PagerDuty, GitHub, Slack, and the incident
runbooks directory. See [ARCHITECTURE.md](./ARCHITECTURE.md) for how each one
is used day-to-day — including how to turn on the self-heal loop with
`/loop 5m` and `runbooks/self-heal.md`.
