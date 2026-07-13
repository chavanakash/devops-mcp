# Datadog Agent: one-time secret setup

The Datadog Agent DaemonSet (`k8s/datadog-agent/`) is deployed by Argo CD like
everything else, but it needs a `DD_API_KEY` that must never be committed to git —
so the `datadog-secret` Secret it reads from is created manually, once, directly
on the cluster.

## Steps

1. Get a Datadog API key: **Organization Settings → API Keys** in the Datadog UI.
2. Open a shell on the node via SSM (no SSH key needed):

   ```bash
   aws ssm start-session --target "$(terraform -chdir=infra/terraform/envs/prod output -raw k3s_node_instance_id)"
   ```

3. Create the secret in the cluster:

   ```bash
   sudo /usr/local/bin/k3s kubectl create namespace datadog --dry-run=client -o yaml \
     | sudo /usr/local/bin/k3s kubectl apply -f -

   sudo /usr/local/bin/k3s kubectl create secret generic datadog-secret \
     --namespace datadog \
     --from-literal api-key=<YOUR_DATADOG_API_KEY>
   ```

4. Argo CD's `selfHeal` will already have the DaemonSet manifest applied and
   crash-looping on the missing secret — it picks up the fix automatically within
   its next reconcile (default: 3 minutes). Confirm:

   ```bash
   sudo /usr/local/bin/k3s kubectl get pods -n datadog
   ```

This secret does not survive a node replacement (it's cluster state, not
Terraform-managed) — redo this after any `terraform apply -replace=...` on the
k3s node.
