# Cluster access: kubeconfig, and checking Argo CD status

Argo CD runs in **core mode** here (application-controller + repo-server + redis
only — no API server, no UI, no Dex, no notifications-controller). The full install
was enough extra RAM demand to tip this 1GiB node into sustained swap-thrashing
even after capping every component's resources (see ARCHITECTURE.md's design
decisions) — core mode is what actually fixed it. The tradeoff: no `argocd login`,
no web UI, no REST API — sync/health status is read directly from the `Application`
custom resource via `kubectl`, which is also how the Kubernetes MCP checks it.

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

## 1. Checking Argo CD app health

With the tunnel + `KUBECONFIG` from step 0:

```bash
kubectl get applications -n argocd
kubectl describe application status-api -n argocd
kubectl describe application datadog-agent -n argocd   # if enable_datadog = true
```

`SYNC STATUS: Synced` + `HEALTH STATUS: Healthy` means the GitOps loop is working
end-to-end: CI pushed an image → bumped the manifest tag → Argo CD noticed the git
change → reconciled the cluster. `describe`'s `Events` section shows the actual
sync history and any errors (image pull failures, manifest validation, etc.).

## 2. If you need the full UI/API back

Re-enabling the full install (API server + UI) means reverting
`infra/terraform/modules/k3s-node/user_data.sh.tpl` to install from
`install.yaml` instead of `core-install.yaml` and re-adding the NodePort +
resource-limit steps that were removed — but expect the swap-thrashing this
runbook exists because of, unless the node is also upgraded off t3.micro.
