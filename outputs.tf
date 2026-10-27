output "handoff" {
  description = "Values to send to Faber once the apply finishes. None of them are secret."
  value = {
    cloud                 = "aws"
    bucket_name           = aws_s3_bucket.this.bucket
    region                = local.region
    account_id            = local.account_id
    role_arn              = one(aws_iam_role.faber[*].arn)
    kms_key_arn           = aws_kms_key.this.arn
    bedrock_enabled       = var.enable_bedrock
    faber_access_enabled  = var.faber_access_enabled
    access_logging        = var.enable_access_logging
    faber_service_account = var.faber_service_account
    module_version        = local.module_version
  }
}

output "bucket_name" {
  description = "Name of the bucket that holds your Faber content."
  value       = aws_s3_bucket.this.bucket
}

output "role_arn" {
  description = "ARN of the role Faber assumes, or null while faber_access_enabled is false."
  value       = one(aws_iam_role.faber[*].arn)
}

output "kms_key_arn" {
  description = "ARN of the AWS KMS key that encrypts the bucket."
  value       = aws_kms_key.this.arn
}

output "log_bucket_name" {
  description = "Name of the bucket that holds the CloudTrail logs, or null when access logging is off."
  value       = one(aws_s3_bucket.logs[*].bucket)
}
