# Plan-only tests for the optional switches.

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
}

variables {
  bucket_name              = "acme-faber-content"
  faber_service_account    = "faber-ws-acme@project-54fc229c-12bb-4421-919.iam.gserviceaccount.com"
  faber_service_account_id = "123456789012345678901"
}

run "bedrock_allows_claude_only" {
  command = plan

  variables {
    enable_bedrock = true
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_iam_role_policy.faber[0].policy).Statement :
      s.Sid == "InvokeClaudeOnBedrock" &&
      toset(s.Action) == toset(["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]) &&
      toset(s.Resource) == toset([
        "arn:aws:bedrock:*::foundation-model/anthropic.*",
        "arn:aws:bedrock:*:111122223333:inference-profile/*anthropic.*",
      ])
    ])
    error_message = "With Bedrock on, Faber may invoke Anthropic models and inference profiles only."
  }

  assert {
    condition     = output.handoff.bedrock_enabled == true
    error_message = "Handoff must report Bedrock as on."
  }
}

run "access_off_removes_the_role" {
  command = plan

  variables {
    faber_access_enabled = false
  }

  assert {
    condition     = length(aws_iam_role.faber) == 0 && length(aws_iam_role_policy.faber) == 0
    error_message = "With access off there must be no Faber role or policy."
  }

  assert {
    condition     = output.handoff.role_arn == null && output.handoff.faber_access_enabled == false
    error_message = "Handoff must show that access is off."
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "acme-faber-content" && aws_kms_key.this.enable_key_rotation
    error_message = "Turning access off must keep the bucket and key."
  }
}

run "logging_off_skips_the_trail" {
  command = plan

  variables {
    enable_access_logging = false
  }

  assert {
    condition     = length(aws_cloudtrail.this) == 0 && length(aws_s3_bucket.logs) == 0
    error_message = "With logging off there must be no trail or log bucket."
  }

  assert {
    condition = !anytrue([
      for s in jsondecode(aws_kms_key.this.policy).Statement :
      startswith(s.Sid, "CloudTrail")
    ])
    error_message = "With logging off, CloudTrail must not be in the key policy."
  }
}

run "custom_settings_are_used" {
  command = plan

  variables {
    role_name                         = "acme-faber"
    role_permissions_boundary         = "arn:aws:iam::111122223333:policy/boundary"
    key_rotation_days                 = 365
    noncurrent_version_retention_days = 7
    tags                              = { team = "it" }
  }

  assert {
    condition     = aws_iam_role.faber[0].name == "acme-faber" && aws_iam_role.faber[0].permissions_boundary == "arn:aws:iam::111122223333:policy/boundary"
    error_message = "Role name and permissions boundary must be applied."
  }

  assert {
    condition     = aws_kms_key.this.rotation_period_in_days == 365
    error_message = "Custom rotation period must be applied."
  }

  assert {
    condition = anytrue([
      for rule in aws_s3_bucket_lifecycle_configuration.this.rule :
      one(rule.noncurrent_version_expiration).noncurrent_days == 7
    ])
    error_message = "Custom retention must be applied."
  }

  assert {
    condition     = aws_s3_bucket.this.tags["team"] == "it" && aws_s3_bucket.this.tags["managed-by"] == "faber-terraform"
    error_message = "Custom tags must be merged with the managed-by tag."
  }
}
