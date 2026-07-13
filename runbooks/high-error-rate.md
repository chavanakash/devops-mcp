# High CPU / error rate

**Triggers:** Datadog monitor `devops-mcp k3s node CPU high` (>85% for 10m), or a
spike in non-2xx responses from `status-api`.

## 1. Look at the dashboard first

```
terraform -chdir=infra/terraform/envs/prod output -raw datadog_dashboard_url
```

Check whether it's a real load spike (unlikely — this is a portfolio demo with
low traffic) or a runaway process/restart loop.

## 2. Check pod status

Via SSM (see [k3s-node-down.md](./k3s-node-down.md) step 3 for the session command):

```bash
kubectl get pods -A
kubectl top pods -A 2>/dev/null || echo "metrics-server not installed — check via docker/containerd stats instead"
kubectl logs -l app=status-api --tail=200
```

Common causes on this stack:

- **status-api crash-looping** — check `kubectl describe pod -l app=status-api`
  for the reason (usually a bad image tag pushed by CI, or the health check
  failing). Roll back by re-running the previous `status-api CI` workflow run,
  or manually: `kubectl set image deployment/status-api status-api=<previous-tag>`.
- **Datadog Agent itself using too much CPU/memory** — it's tuned down (APM/process
  agent disabled) for this reason; if it's still heavy, check
  `k8s/datadog-agent/daemonset.yaml` resource limits and lower them further.
- **Argo CD reconciliation loop** (rare) — `kubectl logs -n argocd deploy/argocd-application-controller`.

## 3. If it's a genuine resource ceiling

This is a single t3.micro (1 vCPU burstable, 1GiB RAM) — it will not scale under
real load. That's expected for a portfolio demo. If this ever needs to hold up
under real traffic, the fix is a bigger instance type (`instance_type` var in
`infra/terraform/modules/k3s-node`), not firefighting.
