# Runbooks

Markdown SOPs for this stack's failure modes. This directory is what the
Incident Runbook MCP (`@modelcontextprotocol/server-filesystem`, read-only) exposes
to Claude — so when something breaks (or the self-heal loop kicks in), Claude can
pull the matching runbook directly into the conversation instead of you searching
for it.

| Runbook | When it fires |
|---|---|
| [self-heal.md](./self-heal.md) | The playbook Claude follows via `/loop` to check pod health and intervene |
| [local-cluster-access.md](./local-cluster-access.md) | kubectl context, Argo CD UI/token, ghcr pull secret, ngrok tunnel setup |
| [high-error-rate.md](./high-error-rate.md) | Datadog CPU/error-rate monitor alert (opt-in) |
| [deploy-failed.md](./deploy-failed.md) | GitHub Actions deploy job fails, or Argo CD app stuck `OutOfSync`/`Degraded` |
| [datadog-agent-setup.md](./datadog-agent-setup.md) | One-time manual step: creating the Datadog Agent's API key secret (opt-in) |
