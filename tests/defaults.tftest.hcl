# Plan-only tests: prevent_destroy on the bucket and key would block the destroy
# step that `terraform test` runs after an apply.

mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111122223333"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn    = "arn:aws:s3:::acme-faber-content"
      region = "us-east-2"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn    = "arn:aws:kms:us-east-2:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
      key_id = "1234abcd-12ab-34cd-56ef-1234567890ab"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111122223333:role/faber-access"
    }
  }
}

variables {
  bucket_name              = "acme-faber-content"
  faber_service_account    = "faber-ws-acme@project-54fc229c-12bb-4421-919.iam.gserviceaccount.com"
  faber_service_account_id = "123456789012345678901"
}

run "bucket_is_private_versioned_and_encrypted" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.force_destroy == false
    error_message = "Bucket must not be force-destroyable."
  }

  assert {
    condition = (
      aws_s3_bucket_public_access_block.this.block_public_acls &&
      aws_s3_bucket_public_access_block.this.block_public_policy &&
      aws_s3_bucket_public_access_block.this.ignore_public_acls &&
      aws_s3_bucket_public_access_block.this.restrict_public_buckets
    )
    error_message = "All four public access block settings must be on."
  }

  assert {
    condition     = one(aws_s3_bucket_ownership_controls.this.rule).object_ownership == "BucketOwnerEnforced"
    error_message = "ACLs must be disabled with BucketOwnerEnforced."
  }

  assert {
    condition     = one(aws_s3_bucket_versioning.this.versioning_configuration).status == "Enabled"
    error_message = "Bucket versioning must be on."
  }

  assert {
    condition = alltrue([
      for rule in aws_s3_bucket_server_side_encryption_configuration.this.rule :
      rule.bucket_key_enabled &&
      one(rule.apply_server_side_encryption_by_default).sse_algorithm == "aws:kms" &&
      one(rule.apply_server_side_encryption_by_default).kms_master_key_id == "arn:aws:kms:us-east-2:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    ])
    error_message = "Bucket must default to SSE-KMS with the module's key and S3 bucket keys."
  }

  assert {
    condition     = aws_s3_bucket.this.tags["managed-by"] == "faber-terraform"
    error_message = "Bucket must carry the managed-by tag."
  }
}

run "bucket_denies_insecure_transport" {
  command = plan

  assert {
    condition = anytrue([
      for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement :
      s.Effect == "Deny" && s.Condition.Bool["aws:SecureTransport"] == "false"
    ])
    error_message = "Bucket policy must deny requests without TLS."
  }
}

run "old_versions_are_pruned" {
  command = plan

  assert {
    condition = anytrue([
      for rule in aws_s3_bucket_lifecycle_configuration.this.rule :
      rule.status == "Enabled" && one(rule.noncurrent_version_expiration).noncurrent_days == 30
    ])
    error_message = "Previous versions must expire after 30 days by default."
  }

  # The attribute is a string in provider 5.x and a number in 6.x.
  assert {
    condition = anytrue([
      for rule in aws_s3_bucket_lifecycle_configuration.this.rule :
      rule.status == "Enabled" && tostring(one(rule.noncurrent_version_expiration).newer_noncurrent_versions) == "4"
    ])
    error_message = "At most 4 previous versions must be kept."
  }
}

run "key_rotates_every_90_days" {
  command = plan

  assert {
    condition     = aws_kms_key.this.enable_key_rotation && aws_kms_key.this.rotation_period_in_days == 90
    error_message = "Key must rotate every 90 days by default."
  }

  assert {
    condition     = aws_kms_key.this.deletion_window_in_days == 30
    error_message = "Key deletion must wait the full 30 days."
  }

  assert {
    condition     = aws_kms_alias.this.name == "alias/faber/acme-faber-content"
    error_message = "Key alias must be named after the bucket."
  }
}

run "key_policy_leaves_use_to_iam" {
  command = plan

  assert {
    condition = alltrue([
      for s in jsondecode(aws_kms_key.this.policy).Statement :
      s.Sid != "AccountAdministers" || s.Principal.AWS == "arn:aws:iam::111122223333:root"
    ])
    error_message = "The account root must administer the key."
  }

  assert {
    condition = !anytrue([
      for s in jsondecode(aws_kms_key.this.policy).Statement :
      can(s.Principal.AWS) && s.Principal.AWS != "arn:aws:iam::111122223333:root"
    ])
    error_message = "The key policy must not name any other AWS principal."
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_kms_key.this.policy).Statement :
      s.Sid == "CloudTrailEncryptsLogs" && s.Condition.StringEquals["aws:SourceArn"] == "arn:aws:cloudtrail:us-east-2:111122223333:trail/faber-acme-faber-content"
    ])
    error_message = "CloudTrail may encrypt with the key only for this trail."
  }
}

run "trust_is_limited_to_the_faber_service_account" {
  command = plan

  assert {
    condition     = length(jsondecode(aws_iam_role.faber[0].assume_role_policy).Statement) == 1
    error_message = "The trust policy must have exactly one statement."
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role.faber[0].assume_role_policy).Statement :
      s.Effect == "Allow" &&
      s.Action == "sts:AssumeRoleWithWebIdentity" &&
      s.Principal.Federated == "accounts.google.com" &&
      keys(s.Condition) == ["StringEquals"] &&
      s.Condition.StringEquals == {
        "accounts.google.com:sub"  = "123456789012345678901"
        "accounts.google.com:aud"  = "123456789012345678901"
        "accounts.google.com:oaud" = "sts.amazonaws.com"
      }
    ])
    error_message = "Only Google tokens for the Faber service account, with audience sts.amazonaws.com, may assume the role."
  }

  assert {
    condition     = aws_iam_role.faber[0].max_session_duration == 3600
    error_message = "Sessions must last at most an hour."
  }
}

run "faber_gets_this_bucket_and_key_only" {
  command = plan

  assert {
    condition = toset(flatten([
      for s in jsondecode(aws_iam_role_policy.faber[0].policy).Statement : s.Resource
      ])) == toset([
      "arn:aws:s3:::acme-faber-content",
      "arn:aws:s3:::acme-faber-content/*",
      "arn:aws:kms:us-east-2:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab",
    ])
    error_message = "Faber's policy must cover only the bucket, its objects and the key."
  }

  assert {
    condition = toset(flatten([
      for s in jsondecode(aws_iam_role_policy.faber[0].policy).Statement : s.Action
      ])) == toset([
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "kms:Decrypt",
      "kms:GenerateDataKey",
    ])
    error_message = "Faber must get object read, write and delete, and key use, and nothing else."
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_iam_role_policy.faber[0].policy).Statement :
      s.Sid == "UseKeyThroughS3" && s.Condition.StringEquals["kms:ViaService"] == "s3.us-east-2.amazonaws.com"
    ])
    error_message = "Faber may use the key only through S3."
  }
}

run "access_logging_is_on_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudtrail.this) == 1 && aws_cloudtrail.this[0].is_multi_region_trail && aws_cloudtrail.this[0].enable_log_file_validation
    error_message = "A multi-region trail with log file validation must be created."
  }

  assert {
    condition     = aws_cloudtrail.this[0].kms_key_id == "arn:aws:kms:us-east-2:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "The trail must be encrypted with the module's key."
  }

  assert {
    condition = anytrue([
      for sel in aws_cloudtrail.this[0].advanced_event_selector :
      anytrue([for f in sel.field_selector : f.field == "resources.ARN" && try(contains(f.starts_with, "arn:aws:s3:::acme-faber-content/"), false)])
    ])
    error_message = "The trail must record object-level events for the Faber bucket."
  }

  assert {
    condition     = aws_s3_bucket.logs[0].bucket == "acme-faber-content-logs"
    error_message = "Logs must go to <bucket_name>-logs."
  }
}

run "no_bedrock_by_default" {
  command = plan

  assert {
    condition = !anytrue([
      for s in jsondecode(aws_iam_role_policy.faber[0].policy).Statement :
      anytrue([for a in flatten([s.Action]) : startswith(a, "bedrock:")])
    ])
    error_message = "Bedrock must be off by default."
  }
}

run "handoff_has_what_faber_needs" {
  command = plan

  assert {
    condition     = output.handoff.cloud == "aws" && output.handoff.bucket_name == "acme-faber-content" && output.handoff.region == "us-east-2"
    error_message = "Handoff must name the cloud, bucket and region."
  }

  assert {
    condition     = output.handoff.role_arn == "arn:aws:iam::111122223333:role/faber-access" && output.handoff.account_id == "111122223333"
    error_message = "Handoff must include the role ARN and account ID."
  }

  assert {
    condition     = output.handoff.kms_key_arn == "arn:aws:kms:us-east-2:111122223333:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    error_message = "Handoff must include the key ARN."
  }

  assert {
    condition     = output.handoff.bedrock_enabled == false && output.handoff.faber_access_enabled == true
    error_message = "Handoff must report the AI and access switches."
  }
}
