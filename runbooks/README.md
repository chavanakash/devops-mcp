# Runbooks

Markdown SOPs for this stack's failure modes. This directory is what the
Incident Runbook MCP (`@modelcontextprotocol/server-filesystem`, read-only) exposes
to Claude — so when PagerDuty pages, Claude can pull the matching runbook directly
into the conversation instead of you searching for it.

| Runbook | When it fires |
|---|---|
| [k3s-node-down.md](./k3s-node-down.md) | EC2 instance / k3s unreachable, status-api uptime check failing |
| [high-error-rate.md](./high-error-rate.md) | Datadog CPU/error-rate monitor alert |
| [deploy-failed.md](./deploy-failed.md) | GitHub Actions deploy job fails, or Argo CD app stuck `OutOfSync`/`Degraded` |
| [argocd-access.md](./argocd-access.md) | Getting the kubeconfig, and checking Argo CD `Application` sync/health (core mode — no UI/CLI) |
| [datadog-agent-setup.md](./datadog-agent-setup.md) | One-time manual step: creating the Datadog Agent's API key secret |
