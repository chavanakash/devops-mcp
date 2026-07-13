# Architecture

This repo is both a portfolio site and the infrastructure that runs it. Every layer
in the diagram below is real: Terraform-provisioned AWS resources, a self-managed
Kubernetes cluster, GitOps deployments, and monitoring — operated end-to-end through
Claude via the Model Context Protocol (MCP).

```
                          ┌─────────────────────────────┐
   PR / push to main ───▶ │  GitHub Actions             │
                          │  - terraform plan/apply      │
                          │  - site build → S3/CloudFront│
                          │  - status-api build → ECR    │
                          └──────────────┬───────────────┘
                                          │ OIDC (no static AWS keys)
                                          ▼
   ┌───────────────────────────────────────────────────────────────┐
   │ AWS (ap-south-1, free tier)                                    │
   │                                                                 │
   │  S3 + CloudFront ───▶ portfolio site (this page)                │
   │                                                                 │
   │  EC2 t3.micro ─── k3s (single node)                             │
   │    ├─ Argo CD (core)   watches k8s/ on this repo, auto-syncs    │
   │    ├─ status-api       live-infra widget backend, proxied on    │
   │    │                   CloudFront's /api/* (no TLS of its own)  │
   │    └─ Datadog Agent    ships host/pod metrics                   │
   │  (no SSH, no public 6443 — admin access via SSM Session Manager)│
   │                                                                 │
   │  AWS Budgets ───▶ email alert at 50/80/100% of a $5/mo cap      │
   └───────────────────────────────────────────────────────────────┘
                                          │
                         Datadog monitors │ PagerDuty escalation │ Slack
                                          ▼
                              ┌───────────────────────┐
                              │ Claude Code + 8 MCPs   │
                              │ (.mcp.json)            │
                              └───────────────────────┘
```

## Design decisions & why

- **k3s on EC2, not EKS.** EKS's control plane costs ~$0.10/hr forever — never
  free. A single t3.micro running k3s stays inside the AWS free tier and still
  exercises real Kubernetes primitives (Deployments, Services, RBAC, GitOps).
- **No SSH, no public API server.** The node's security group allows exactly one
  inbound port: the status-api NodePort (the public demo, itself only reachable
  indirectly — through CloudFront's `/api/*` proxy, since status-api has no TLS
  of its own and browsers block HTTPS-page-to-HTTP-API fetches). Everything
  administrative — `kubectl`, troubleshooting — goes through AWS Systems Manager
  Session Manager, which needs no open ports and no SSH key management. See
  `infra/terraform/modules/k3s-node`.
- **Argo CD "core" install, not the full one.** The full install (API server, UI,
  Dex, notifications-controller, applicationset-controller — 7 components) was
  enough extra RAM demand to tip this 1GiB node into sustained swap-thrashing
  (measured 70-97% iowait via `vmstat`) even after capping every component's
  resources. Core mode — just application-controller, repo-server, and redis —
  is what actually fixed it. The tradeoff: no Argo CD web UI or REST API, so
  Application sync/health status is read via the Kubernetes MCP (`kubectl get
  applications -n argocd`) instead of a dedicated Argo CD MCP.
- **GitOps via Argo CD, image tags bumped by CI.** `status-api-ci.yml` builds and
  pushes an image to ECR, then edits `k8s/status-api/kustomization.yaml`'s image
  tag and commits it back to `main`. Argo CD's `selfHeal` picks up the change —
  the cluster's state always matches what's in Git, not what a CI job happened to
  `kubectl apply`.
- **OIDC, not access keys, for CI.** `infra/terraform/modules/github-oidc` creates
  two IAM roles GitHub Actions assumes via short-lived tokens: a read-only `plan`
  role for PRs, and a scoped `deploy` role (gated by a GitHub Environment requiring
  manual approval) for applies to `main`. No AWS credentials are ever stored as
  GitHub secrets.
- **A budget alarm applied before anything else.** `infra/terraform/modules/budget-alarm`
  emails at 50/80/100% of a low monthly cap — a safety net independent of whether
  this AWS account is still inside its 12-month free-tier window.
- **Secrets never touch Terraform state or git.** Datadog/PagerDuty/Slack API keys
  are read from environment variables by their Terraform providers (never passed as
  `variable` values) and, for the in-cluster Datadog Agent, created as a Kubernetes
  Secret by hand via SSM (see `runbooks/datadog-agent-setup.md`) rather than piped
  through Terraform's `kubernetes` provider — consistent with the cluster having no
  Terraform-reachable API endpoint in the first place.

## The MCPs

Claude's project-level MCP config (`.mcp.json`) wires up eight servers, covering
seven of the "MCP Stack Map" categories — Infra, Observability, CI/CD, Comms &
Response. The eighth ("Argo CD") isn't a separate server: Argo CD runs in "core"
mode here (no API server/UI — see the design decisions above), so Application
sync/health status is read through the Kubernetes MCP instead, by querying the
`Application` custom resource directly. Package names below were verified against
each project's own docs/repo, not guessed — worth re-checking for updates before
first use, since this ecosystem moves fast.

| # | MCP | Package / endpoint | What it's for here |
|---|---|---|---|
| 1 | Kubernetes | [`mcp-server-kubernetes`](https://github.com/Flux159/mcp-server-kubernetes) (npm) | Inspect pods/events/logs, and Argo CD `Application` sync/health, on the k3s node via the kubeconfig pulled over SSM |
| 2 | Terraform | [`hashicorp/terraform-mcp-server`](https://github.com/hashicorp/terraform-mcp-server) (Docker) | Review plans, explain diffs, look up registry docs while editing `infra/terraform/` |
| 3 | AWS | [`awslabs.aws-api-mcp-server`](https://github.com/awslabs/mcp) (uvx) | Query live AWS resources, IAM, and cost against the `dockerizzz` profile |
| 4 | Datadog | [Datadog's hosted MCP server](https://docs.datadoghq.com/bits_ai/mcp_server/) (remote HTTP) | Read the dashboard/monitors defined in `infra/terraform/modules/datadog` |
| 5 | PagerDuty | [`pagerduty-mcp-server`](https://github.com/PagerDuty/pagerduty-mcp-server) (PyPI/uvx, official) | Check incidents, on-call state, escalation policy |
| 6 | GitHub | [`github-mcp-server`](https://github.com/github/github-mcp-server) (Docker, official) | Review PRs, open issues, inspect Actions runs |
| 7 | Slack | [`@modelcontextprotocol/server-slack`](https://www.npmjs.com/package/@modelcontextprotocol/server-slack) (npm, official reference) | Post deploy/incident updates, read thread context |
| 8 | Incident Runbook | [`@modelcontextprotocol/server-filesystem`](https://www.npmjs.com/package/@modelcontextprotocol/server-filesystem) (npm, official, read-only) | Serve `runbooks/*.md` directly into the conversation during an incident |

### Example prompts once this is wired up

- *"The status-api uptime check just paged — walk the k3s-node-down runbook and
  tell me what you find."* → Incident Runbook MCP surfaces the SOP, PagerDuty MCP
  confirms the open incident, Kubernetes MCP checks pod status.
- *"Is there config drift between what's applied and what's in `infra/terraform/`?"*
  → Terraform MCP + AWS MCP cross-check.
- *"Did `status-api` actually sync after the last merge?"* → Kubernetes MCP,
  reading the `Application` resource's `status.sync`/`status.health` fields.

## Repo layout

```
site/               Astro portfolio website
apps/status-api/    small service powering the site's "live infra" widget
infra/terraform/    all infrastructure as code (bootstrap/, envs/prod/, modules/)
k8s/                Argo CD Application manifests + status-api / datadog-agent Kustomize bases
runbooks/           incident SOPs (source for the Incident Runbook MCP)
.github/workflows/  CI/CD (terraform plan/apply, site deploy, status-api build)
.mcp.json           Claude Code MCP server registrations
SETUP.md            one-time checklist: accounts, secrets, and manual steps
```
