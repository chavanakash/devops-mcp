# High CPU / error rate

**Triggers:** Datadog monitor for high CPU (opt-in — see `runbooks/datadog-agent-setup.md`),
or a spike in non-2xx responses from `status-api`.

## 1. Check pod status

```bash
kubectl config use-context docker-desktop
kubectl get pods -A
kubectl top pods -A 2>/dev/null || echo "metrics-server not available"
kubectl logs -l app=status-api --tail=200
```

Common causes on this stack — see [self-heal.md](./self-heal.md) for the full
diagnosis/remediation playbook per failure mode. Quick pointers:

- **status-api crash-looping** — usually a bad image tag pushed by CI, or the
  health check failing. `kubectl rollout undo deployment/status-api -n default`
  for immediate mitigation, then fix the source (see self-heal.md).
- **Datadog Agent itself using too much CPU/memory** (if enabled) — check
  `k8s/datadog-agent/daemonset.yaml`'s resource limits.
- **Argo CD reconciliation loop** (rare) —
  `kubectl logs -n argocd statefulset/argocd-application-controller`.

## 2. If it's a genuine resource ceiling

Docker Desktop's Kubernetes runs inside whatever CPU/memory you've allocated it
(Docker Desktop → Settings → Resources). If the whole cluster is under real
pressure, not just one pod, that's a Docker Desktop resource allocation to bump,
not something to firefight at the pod level.
