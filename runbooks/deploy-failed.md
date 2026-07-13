# Deploy failed / Argo CD stuck OutOfSync or Degraded

**Triggers:** a GitHub Actions workflow run fails (red X), or `kubectl describe
application status-api -n argocd` shows anything other than `Synced` + `Healthy`
(see [argocd-access.md](./argocd-access.md) — Argo CD runs in core/CLI-less mode
here).

## 1. Which layer failed?

| Symptom | Look at |
|---|---|
| `terraform plan`/`apply` workflow red | Job logs — usually a provider auth issue (OIDC role misconfigured) or a real plan diff conflict |
| `deploy site` workflow red | Usually `npm run build` failure (bad Astro/TS) or an S3/CloudFront permissions issue on the deploy role |
| `status-api CI` workflow red | Docker build failure, or the `git push` step rejected (branch protection requiring PRs — see note below) |
| Argo CD app `OutOfSync` | Manifest in `k8s/` doesn't match cluster state — check `kubectl describe application <name> -n argocd`'s `Events` |
| Argo CD app `Degraded` | Pods aren't healthy — see [high-error-rate.md](./high-error-rate.md) or [k3s-node-down.md](./k3s-node-down.md) |

## 2. GitHub Actions auth failures

If a workflow fails at the `configure-aws-credentials` step:

- Confirm the repo has `AWS_PLAN_ROLE_ARN` / `AWS_DEPLOY_ROLE_ARN` secrets set
  (from `terraform output github_oidc_plan_role_arn` / `github_oidc_deploy_role_arn`).
- Confirm the OIDC trust policy's `sub` condition matches — it's scoped to
  `repo:<owner>/<repo>:ref:refs/heads/main` and `repo:<owner>/<repo>:environment:production`.
  A fork, a rename, or a different branch won't match and will be denied by design.

## 3. Argo CD access

```bash
aws ssm start-session --target "$(terraform -chdir=infra/terraform/envs/prod output -raw k3s_node_instance_id)" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["6443"],"localPortNumber":["6443"]}'
```

In another terminal, with a kubeconfig pointed at `localhost:6443` (or just use
`kubectl` inside the SSM shell directly against the in-cluster kubeconfig):

```bash
kubectl get applications -n argocd
kubectl describe application status-api -n argocd
```

## 4. status-api CI push rejected

`status-api-ci.yml` commits the new image tag straight to `main` via `git push`.
If branch protection on `main` requires PRs, this step will fail by design — either
relax protection for the `github-actions[bot]` actor, or switch that step to open a
PR instead of pushing directly (trade GitOps auto-deploy speed for review).
