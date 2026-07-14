# Datadog Agent: one-time secret setup (opt-in)

The Datadog Agent DaemonSet (`k8s/datadog-agent/`) isn't deployed by default —
`scripts/setup-local-cluster.sh` only creates its Argo CD Application when
`DEPLOY_DATADOG_AGENT=true`. It needs a `DD_API_KEY` that must never be
committed to git, so the `datadog-secret` Secret it reads from is created
manually, once, directly on the cluster.

## Steps

1. Get a Datadog API key: **Organization Settings → API Keys** in the Datadog UI.
2. With `kubectl config use-context docker-desktop`:

   ```bash
   kubectl create namespace datadog --dry-run=client -o yaml | kubectl apply -f -

   kubectl create secret generic datadog-secret \
     --namespace datadog \
     --from-literal api-key=<YOUR_DATADOG_API_KEY>
   ```

3. Re-run `DEPLOY_DATADOG_AGENT=true ./scripts/setup-local-cluster.sh` (or apply
   the `datadog-agent` Argo CD Application manually) if you haven't already.
   Argo CD's `selfHeal` picks up the secret automatically within its next
   reconcile. Confirm:

   ```bash
   kubectl get pods -n datadog
   ```

This secret is cluster state, not tracked anywhere — redo it if you ever tear
down and recreate the local cluster.
