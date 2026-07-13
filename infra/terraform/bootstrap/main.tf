# Bootstrap: creates the S3 bucket + DynamoDB lock table that `envs/prod` uses as its
# remote state backend. This has a chicken-and-egg problem (the backend can't manage
# the resources it depends on), so it intentionally keeps its own local state — applied
# once, rarely touched again.

data "aws_caller_identity" "current" {}

locals {
  state_bucket_name = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "tf_state" {
  bucket = local.state_bucket_name

  # Portfolio project, not a critical prod system: allow the bucket to be torn down
  # cleanly (after emptying it) instead of requiring a manual force-destroy dance.
  force_destroy = true

  tags = {
    Project   = var.project
    ManagedBy = "terraform-bootstrap"
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tf_lock" {
  name         = "${var.project}-tfstate-lock"
  billing_mode = "PAY_PER_REQUEST" # free tier: 25 GB storage, no idle cost
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Project   = var.project
    ManagedBy = "terraform-bootstrap"
  }
}
