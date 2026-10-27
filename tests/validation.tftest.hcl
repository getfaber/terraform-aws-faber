mock_provider "aws" {}

variables {
  bucket_name              = "acme-faber-content"
  faber_service_account    = "faber-ws-acme@project-54fc229c-12bb-4421-919.iam.gserviceaccount.com"
  faber_service_account_id = "123456789012345678901"
}

run "rejects_non_faber_service_account" {
  command = plan

  variables {
    faber_service_account = "someone@evil-project.iam.gserviceaccount.com"
  }

  expect_failures = [var.faber_service_account]
}

run "rejects_faber_lookalike_project" {
  command = plan

  variables {
    faber_service_account = "faber-ws-acme@project-54fc229c-12bb-4421-918.iam.gserviceaccount.com"
  }

  expect_failures = [var.faber_service_account]
}

run "rejects_short_service_account_id" {
  command = plan

  variables {
    faber_service_account_id = "12345678901234567890"
  }

  expect_failures = [var.faber_service_account_id]
}

run "rejects_service_account_email_as_id" {
  command = plan

  variables {
    faber_service_account_id = "faber-ws-acme@project-54fc229c-12bb-4421-919.iam.gserviceaccount.com"
  }

  expect_failures = [var.faber_service_account_id]
}

run "rejects_bucket_with_dots" {
  command = plan

  variables {
    bucket_name = "acme.faber.content"
  }

  expect_failures = [var.bucket_name]
}

run "rejects_reserved_bucket_suffix" {
  command = plan

  variables {
    bucket_name = "acme-faber-s3alias"
  }

  expect_failures = [var.bucket_name]
}

run "rejects_bucket_too_long_for_log_bucket" {
  command = plan

  variables {
    bucket_name = "a23456789012345678901234567890123456789012345678901234567890"
  }

  expect_failures = [var.bucket_name]
}

run "rejects_double_dash_bucket" {
  command = plan

  variables {
    bucket_name = "acme--content"
  }

  expect_failures = [var.bucket_name]
}

run "accepts_58_character_bucket" {
  command = plan

  variables {
    bucket_name = "a234567890123456789012345678901234567890123456789012345678"
  }
}

run "rejects_59_character_bucket" {
  command = plan

  variables {
    bucket_name = "a2345678901234567890123456789012345678901234567890123456789"
  }

  expect_failures = [var.bucket_name]
}

run "rejects_rotation_below_90_days" {
  command = plan

  variables {
    key_rotation_days = 30
  }

  expect_failures = [var.key_rotation_days]
}

run "rejects_rotation_above_2560_days" {
  command = plan

  variables {
    key_rotation_days = 3000
  }

  expect_failures = [var.key_rotation_days]
}

run "rejects_bad_permissions_boundary" {
  command = plan

  variables {
    role_permissions_boundary = "boundary"
  }

  expect_failures = [var.role_permissions_boundary]
}
