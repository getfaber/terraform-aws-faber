# Faber signs in with a Google ID token for its workspace service account, so
# there is no AWS account or access key on Faber's side. AWS maps the token's
# claims to these keys: sub and azp (":aud") are the service account's numeric
# ID, and aud (":oaud") is the audience Faber requests.
resource "aws_iam_role" "faber" {
  count = var.faber_access_enabled ? 1 : 0

  name        = var.role_name
  description = "Lets Faber (${var.faber_service_account}) read and write its content in s3://${var.bucket_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "accounts.google.com" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "accounts.google.com:sub"  = var.faber_service_account_id
          "accounts.google.com:aud"  = var.faber_service_account_id
          "accounts.google.com:oaud" = "sts.amazonaws.com"
        }
      }
    }]
  })
  max_session_duration = 3600
  permissions_boundary = var.role_permissions_boundary
  tags                 = local.tags
}

# Read, write and delete objects in this bucket, and use the key only through
# S3 in the bucket's region. Nothing else: no bucket settings, no IAM, no other
# buckets.
locals {
  faber_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid      = "ListBucket"
          Effect   = "Allow"
          Action   = "s3:ListBucket"
          Resource = aws_s3_bucket.this.arn
        },
        {
          Sid      = "ReadWriteObjects"
          Effect   = "Allow"
          Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
          Resource = "${aws_s3_bucket.this.arn}/*"
        },
        {
          Sid       = "UseKeyThroughS3"
          Effect    = "Allow"
          Action    = ["kms:Decrypt", "kms:GenerateDataKey"]
          Resource  = aws_kms_key.this.arn
          Condition = { StringEquals = { "kms:ViaService" = "s3.${local.region}.${local.dns_suffix}" } }
        },
      ],
      # Cross-region inference profiles route to the foundation model in other
      # regions, so the model ARNs can't be pinned to one region.
      [for statement in [{
        Sid    = "InvokeClaudeOnBedrock"
        Effect = "Allow"
        Action = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        Resource = [
          "arn:${local.partition}:bedrock:*::foundation-model/anthropic.*",
          "arn:${local.partition}:bedrock:*:${local.account_id}:inference-profile/*anthropic.*",
        ]
      }] : statement if var.enable_bedrock],
    )
  })
}

resource "aws_iam_role_policy" "faber" {
  count = var.faber_access_enabled ? 1 : 0

  name   = "faber-content-access"
  role   = aws_iam_role.faber[0].id
  policy = local.faber_policy
}
