# k3s node down / status-api unreachable

**Triggers:** Datadog synthetic uptime check on `status-api.uptime` fails; the
portfolio site's "Live infra" widget shows "Cluster unreachable"; PagerDuty pages
via the `devops-mcp-status-api` service.

## 1. Confirm it's real

```bash
curl -sf "$(cd infra/terraform/envs/prod && terraform output -raw status_api_url)/health"
```

If this times out, the node itself is likely down (not just the app). If it
returns a non-200 or connection refused but the instance is reachable, skip to
[high-error-rate.md](./high-error-rate.md) instead.

## 2. Check the instance

```bash
aws ec2 describe-instance-status --instance-ids "$(cd infra/terraform/envs/prod && terraform output -raw k3s_node_instance_id)"
```

- **Instance stopped/terminated** — someone (likely a cost-control action, or a
  free-tier boundary) stopped it. Start it via the AWS console/CLI; k3s and Argo CD
  come back up automatically (`k3s.service` is enabled).
- **Instance running but unreachable** — likely OOM on the 1GiB node (k3s + Argo CD
  + Datadog Agent is tight). Continue to step 3.

## 3. Get a shell (no SSH — via SSM)

```bash
aws ssm start-session --target "$(cd infra/terraform/envs/prod && terraform output -raw k3s_node_instance_id)"
```

Then on the instance:

```bash
sudo systemctl status k3s
sudo journalctl -u k3s --since "20 min ago" | tail -100
free -h            # check swap didn't disappear / OOM killer fired
sudo /usr/local/bin/k3s kubectl get pods -A
```

## 4. Common fixes

- `k3s` service crashed: `sudo systemctl restart k3s`.
- Pods evicted for memory pressure: `kubectl get events -A --sort-by=.lastTimestamp`
  to see which one, then check if it needs a lower memory `limits` value in its
  manifest (see `k8s/status-api/deployment.yaml`, `k8s/datadog-agent/daemonset.yaml`).
- Swap missing (e.g. after a reboot lost `/etc/fstab` for some reason):
  `sudo swapon /swapfile` — the user-data script adds it to `/etc/fstab` on first
  boot, so a normal reboot should preserve it.

## 5. If the instance is unrecoverable

This node is stateless (GitOps: everything is redeployed from `main` by Argo CD).
Safe to terminate and let Terraform recreate it:

```bash
cd infra/terraform/envs/prod
terraform apply -replace=module.k3s_node.aws_instance.node
```

Re-apply the Datadog Agent secret afterwards (see
[datadog-agent-setup.md](./datadog-agent-setup.md)) — it isn't managed by Terraform
and won't survive a node replacement.
