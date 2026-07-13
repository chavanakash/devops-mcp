# Cluster access: kubeconfig, and Argo CD UI/CLI + the MCP token

Argo CD is bootstrapped automatically by the k3s node's user-data (install +
`status-api`/`datadog-agent` Applications + a NodePort on the node so it's reachable
the same way as `kubectl` — see `infra/terraform/modules/k3s-node/user_data.sh.tpl`).
Nothing here needs an inbound security-group rule: SSM Session Manager's port
forwarding tunnels through the SSM agent, not the network, so it reaches the
NodePort regardless of what the SG allows.

## 0. kubectl (fetch the kubeconfig, once)

The cluster's API server is never exposed publicly (see `k3s-node-down.md`'s note
on the SG). Get the kubeconfig via an SSM shell:

```bash
aws ssm start-session --target "$(terraform -chdir=infra/terraform/envs/prod output -raw k3s_node_instance_id)"
# inside the session:
sudo cat /etc/rancher/k3s/k3s.yaml
```

Copy that output to `~/.kube/devops-mcp.yaml` on your machine. Its `server:` field
is already `https://127.0.0.1:6443` — k3s's default — which is exactly what you
want once you open a tunnel to port 6443:

```bash
aws ssm start-session --target "$(terraform -chdir=infra/terraform/envs/prod output -raw k3s_node_instance_id)" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["6443"],"localPortNumber":["6443"]}'
```

Leave that running, then in another terminal:

```bash
export KUBECONFIG=~/.kube/devops-mcp.yaml
kubectl get nodes   # should show the k3s node, Ready
```

This is also the `KUBECONFIG` value the Kubernetes MCP in `.mcp.json` needs.

## 1. Open a tunnel (Argo CD)

```bash
aws ssm start-session --target "$(terraform -chdir=infra/terraform/envs/prod output -raw k3s_node_instance_id)" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["30444"],"localPortNumber":["8443"]}'
```

Leave this running (alongside, or instead of, the port-6443 tunnel above — they're
independent). The UI is now at `https://localhost:8443` (self-signed cert — your
browser/CLI will warn, that's expected) and the CLI/API at `localhost:8443`.

## 2. First login (admin)

Get the auto-generated initial admin password via another SSM shell
(`aws ssm start-session --target <instance-id>`):

```bash
sudo /usr/local/bin/k3s kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Then, from your machine (with the tunnel from step 1 open):

```bash
argocd login localhost:8443 --insecure --username admin --password '<password from above>'
argocd account update-password   # change it from the auto-generated one
```

## 3. Generate the token Claude's Argo CD MCP uses

User-data already created a read-only `claude` account (can view app/sync status,
cannot trigger syncs or edit anything — see the RBAC policy in user-data). Generate
its token while logged in as admin:

```bash
argocd account generate-token --account claude
```

Set that as `ARGOCD_API_TOKEN`, and `ARGOCD_BASE_URL=https://localhost:8443` (with
the SSM tunnel from step 1 running), wherever you run `claude` with this repo's
`.mcp.json`.

## 4. Checking app health without the UI

```bash
argocd app list
argocd app get status-api
argocd app get datadog-agent
```

`Synced` + `Healthy` on both means the GitOps loop is working end-to-end: CI pushed
an image → bumped the manifest tag → Argo CD noticed the git change → reconciled
the cluster.
