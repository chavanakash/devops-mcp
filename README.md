# DevOps Portfolio — Claude-Managed AI SRE Stack

A personal DevOps portfolio: a real portfolio website, deployed on real AWS infrastructure,
where the infrastructure itself is inspected and operated through Claude using the
Model Context Protocol (MCP) — mirroring a real AI-SRE workflow.

> Status: 🚧 work in progress. See [ARCHITECTURE.md](./ARCHITECTURE.md) for the full
> design, or [SETUP.md](./SETUP.md) for the one-time deployment checklist.

## Live

- Portfolio: _(CloudFront URL — added once deployed)_
- Live infra demo widget: pulled from a `status-api` service running on a self-managed
  k3s cluster, deployed via Argo CD GitOps.

## What this project demonstrates

| Layer | Tooling |
|---|---|
| Frontend | Astro portfolio site, deployed to S3 + CloudFront |
| IaC | Terraform (modular, remote state, plan-on-PR / apply-on-merge) |
| Compute | k3s on a single free-tier EC2 instance |
| CI/CD | GitHub Actions, GitOps via Argo CD, OIDC (no long-lived AWS keys in CI) |
| Observability | Datadog dashboards/monitors as code |
| Incident response | PagerDuty escalation policies + Slack notifications + markdown runbooks |
| AI operations | Claude Code driving all of the above through 8 MCP servers |

## Repo layout

```
site/               Astro portfolio website
apps/status-api/    small service powering the site's "live infra" widget
infra/terraform/    all infrastructure as code
k8s/                Argo CD + status-api Kubernetes manifests
runbooks/           incident SOPs (source for the Incident Runbook MCP)
.github/workflows/  CI/CD
.mcp.json           Claude Code MCP server registrations
SETUP.md            one-time deployment checklist
```

## Running Claude against this infra

This repo ships a project-level `.mcp.json` registering MCP servers for Kubernetes
(which also covers Argo CD's `Application` status — it runs headless here),
Terraform, AWS, Datadog, PagerDuty, GitHub, Slack, and the incident runbooks
directory. See [ARCHITECTURE.md](./ARCHITECTURE.md) for how each one is used day-to-day.
