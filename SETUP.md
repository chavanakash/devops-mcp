# Setup checklist

Everything in this repo is written and validated (`terraform validate`, Astro
build, Docker build all pass locally). What's left is real-world setup that only
you can do — account creation, secrets, and the first `terraform apply` against
your AWS account. Follow this in order.

## 1. Accounts to create (free tiers)

| Service | What you need | Where |
|---|---|---|
| Datadog | API key + Application key | Organization Settings → API Keys / Application Keys |
| PagerDuty | Account (free trial), API token | Integrations → API Access Keys |
| Slack | A workspace + an Incoming Webhook | api.slack.com/apps → Incoming Webhooks |
| GitHub | Fix `gh auth login` (currently expired) | `gh auth login` |

## 2. Create the GitHub repo

Once `gh auth login` succeeds:

```bash
gh repo create devops-mcp --public --source=. --remote=origin
```

(Or create it in the GitHub UI and `git remote add origin <url>`.) Confirm the
`owner/repo` matches `terraform.tfvars`' `github_repo`.

## 3. Bootstrap Terraform state (one-time, local state)

```bash
cd infra/terraform/bootstrap
terraform init
terraform apply
```

Note the `state_bucket` output, then:

```bash
cd ../envs/prod
cp backend.hcl.example backend.hcl   # fill in the account ID from the output above
cp terraform.tfvars.example terraform.tfvars   # fill in github_repo, pagerduty_user_email
terraform init -backend-config=backend.hcl
```

## 4. Export secrets for the first local apply

```bash
export DD_API_KEY=...
export DD_APP_KEY=...
export PAGERDUTY_TOKEN=...
```

## 5. Review, then apply

```bash
terraform plan    # read it — this creates real (free-tier) AWS resources
terraform apply
```

This provisions: the budget alarm, S3+CloudFront, the k3s EC2 node (which
bootstraps k3s + Argo CD + the status-api and datadog-agent Argo CD Applications
via user-data), the ECR repo, the GitHub OIDC roles, and the Datadog/PagerDuty
config.

Grab the outputs — you'll need them next:

```bash
terraform output
```

## 6. Configure the GitHub repo

**Secrets** (Settings → Secrets and variables → Actions → Secrets):

| Name | Value |
|---|---|
| `AWS_PLAN_ROLE_ARN` | `terraform output -raw github_oidc_plan_role_arn` |
| `AWS_DEPLOY_ROLE_ARN` | `terraform output -raw github_oidc_deploy_role_arn` |
| `DD_API_KEY`, `DD_APP_KEY` | from step 1 |
| `PAGERDUTY_TOKEN` | from step 1 |
| `SLACK_WEBHOOK_URL` | from step 1 |

**Variables** (same page, Variables tab):

| Name | Value |
|---|---|
| `AWS_REGION` | `ap-south-1` |
| `TF_STATE_BUCKET` | `terraform -chdir=infra/terraform/bootstrap output -raw state_bucket` |
| `TF_STATE_LOCK_TABLE` | `terraform -chdir=infra/terraform/bootstrap output -raw lock_table` |
| `ALERT_EMAIL` | your email |
| `PAGERDUTY_USER_EMAIL` | your PagerDuty account email |
| `SITE_BUCKET` | `terraform output -raw site_bucket` |
| `CLOUDFRONT_DISTRIBUTION_ID` | `terraform output -raw cloudfront_distribution_id` |
| `ECR_REPOSITORY` | `terraform output -raw ecr_repository_url` (just the repo name after the last `/`) |
| `STATUS_API_URL` | `terraform output -raw status_api_url` |

**Environment**: create a `production` environment (Settings → Environments) with
yourself as a required reviewer — this is the manual-approval gate on
`terraform apply` and deploys.

## 7. Push

```bash
git add -A
git commit -m "Initial commit: DevOps portfolio + AI SRE stack"
git push -u origin main
```

This triggers `site-deploy.yml` and `status-api-ci.yml` for the first time.

## 8. Datadog Agent secret (manual, cluster-side)

See [runbooks/datadog-agent-setup.md](./runbooks/datadog-agent-setup.md) — one
`kubectl create secret` command over an SSM session.

## 9. Cluster access: kubeconfig + Argo CD token

See [runbooks/argocd-access.md](./runbooks/argocd-access.md) for the full
walkthrough (all via SSM — no SSH, no open ports beyond status-api). Short version:

1. Pull the kubeconfig from the node, point it at an SSM tunnel to port 6443 →
   this is your `KUBECONFIG` for the Kubernetes MCP.
2. Open a second SSM tunnel to Argo CD's NodePort (30444 → local 8443), log in as
   `admin` with the auto-generated password, change it.
3. Generate a token for the read-only `claude` account user-data already created →
   this is your `ARGOCD_API_TOKEN` (`ARGOCD_BASE_URL=https://localhost:8443`).

## 10. Wire Claude up

```bash
export AWS_PROFILE=...        # your AWS CLI profile
export KUBECONFIG=~/.kube/devops-mcp.yaml   # from step 9
export DD_API_KEY=... DD_APP_KEY=...
export PAGERDUTY_API_TOKEN=...
export GITHUB_PERSONAL_ACCESS_TOKEN=...
export ARGOCD_BASE_URL=https://localhost:8443 ARGOCD_API_TOKEN=...   # from step 9
export SLACK_BOT_TOKEN=... SLACK_TEAM_ID=...
claude mcp list   # should show all 9 servers from .mcp.json connected
```

Keep both SSM tunnels from step 9 running while `claude` is — the Kubernetes and
Argo CD MCPs both go through them.

## 11. Fill in real content

- `site/src/components/About.astro`, `Hero.astro`, `Projects.astro`, `Footer.astro`
  — swap placeholder bio/links for the real thing.
- `README.md` — add the live CloudFront URL once step 7 finishes.
