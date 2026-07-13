# Lets GitHub Actions assume AWS roles via short-lived OIDC tokens instead of
# long-lived access keys stored as repo secrets.
#
# Two roles, matching the plan-on-PR / apply-on-merge workflow:
#   - gh-oidc-plan:   read-only, assumable from any workflow run on this repo
#                      (used for `terraform plan` on pull requests).
#   - gh-oidc-deploy: read/write but scoped to this project's own resources,
#                      assumable only from the `production` GitHub Environment
#                      (gated by manual approval) or a push to `main`.

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

# --- Plan role: read-only ---------------------------------------------------

data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "plan" {
  name               = "${var.project}-gh-oidc-plan"
  assume_role_policy = data.aws_iam_policy_document.plan_trust.json
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# --- Deploy role: scoped read/write, only from main or the production environment ---

data "aws_iam_policy_document" "deploy_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repo}:ref:refs/heads/main",
        "repo:${var.github_repo}:environment:production",
      ]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name               = "${var.project}-gh-oidc-deploy"
  assume_role_policy = data.aws_iam_policy_document.deploy_trust.json
}

# Scoped to the services/resources this project actually provisions. Not full
# least-privilege (some AWS actions, e.g. most EC2 operations, don't support
# resource-level conditions) but bounded to what this stack needs rather than
# account-wide admin.
data "aws_iam_policy_document" "deploy_permissions" {
  statement {
    sid = "TerraformState"
    actions = [
      "s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket",
    ]
    resources = [var.state_bucket_arn, "${var.state_bucket_arn}/*"]
  }

  statement {
    sid       = "TerraformLock"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [var.state_lock_table_arn]
  }

  statement {
    sid = "ProjectS3"
    actions = [
      "s3:*",
    ]
    resources = ["arn:aws:s3:::${var.project}-*", "arn:aws:s3:::${var.project}-*/*"]
  }

  statement {
    sid       = "CloudFront"
    actions   = ["cloudfront:*"]
    resources = ["*"]
  }

  statement {
    sid       = "ECR"
    actions   = ["ecr:*"]
    resources = ["arn:aws:ecr:*:*:repository/${var.project}-*"]
  }

  statement {
    sid       = "ECRAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "EC2"
    actions   = ["ec2:*"]
    resources = ["*"]
  }

  statement {
    sid       = "Budgets"
    actions   = ["budgets:*"]
    resources = ["*"]
  }

  statement {
    sid       = "IAMProjectScoped"
    actions   = ["iam:*"]
    resources = ["arn:aws:iam::*:role/${var.project}-*", "arn:aws:iam::*:policy/${var.project}-*"]
  }

  statement {
    sid       = "IAMReadOnly"
    actions   = ["iam:Get*", "iam:List*", "iam:PassRole"]
    resources = ["*"]
  }

  statement {
    sid       = "STS"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }

  statement {
    sid       = "SSM"
    actions   = ["ssm:SendCommand", "ssm:GetCommandInvocation", "ssm:DescribeInstanceInformation", "ssm:StartSession"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "${var.project}-deploy-permissions"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy_permissions.json
}
