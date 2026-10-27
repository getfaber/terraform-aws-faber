# The key policy leaves all key use to IAM policies in this account (the root
# statement), so the Faber role's own policy in iam.tf decides what it can do,
# and deleting that role never leaves a dangling principal here.
locals {
  key_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Sid       = "AccountAdministers"
        Effect    = "Allow"
        Principal = { AWS = "arn:${local.partition}:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      }],
      [for statement in [
        {
          Sid       = "CloudTrailEncryptsLogs"
          Effect    = "Allow"
          Principal = { Service = "cloudtrail.amazonaws.com" }
          Action    = "kms:GenerateDataKey*"
          Resource  = "*"
          Condition = {
            StringEquals = { "aws:SourceArn" = local.trail_arn }
            StringLike   = { "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:${local.partition}:cloudtrail:*:${local.account_id}:trail/*" }
          }
        },
        {
          Sid       = "CloudTrailDescribesKey"
          Effect    = "Allow"
          Principal = { Service = "cloudtrail.amazonaws.com" }
          Action    = "kms:DescribeKey"
          Resource  = "*"
          Condition = {
            StringEquals = { "aws:SourceArn" = local.trail_arn }
          }
        },
      ] : statement if var.enable_access_logging],
    )
  })
}

# Scheduling this key for deletion would make every object in the bucket
# unreadable once the waiting period ends. prevent_destroy stops a stray
# `terraform destroy` from doing that.
resource "aws_kms_key" "this" {
  description             = "Encrypts Faber content in s3://${var.bucket_name}"
  enable_key_rotation     = true
  rotation_period_in_days = var.key_rotation_days
  deletion_window_in_days = 30
  policy                  = local.key_policy
  tags                    = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "this" {
  name          = "alias/faber/${var.bucket_name}"
  target_key_id = aws_kms_key.this.key_id
}

# Object-level access is recorded by the CloudTrail data events in logging.tf
# rather than by S3 server access logs.
#trivy:ignore:AVD-AWS-0089
resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = false
  tags          = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.this.arn
    }
  }
}

# Two rules, so a previous version goes when it's older than the retention
# period OR when 4 newer previous versions exist. A single S3 rule can only
# express "older than AND beyond the newest 4".
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }

    expiration {
      expired_object_delete_marker = true
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "keep-at-most-4-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days           = 1
      newer_noncurrent_versions = 4
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.this]
}
