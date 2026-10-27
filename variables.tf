variable "bucket_name" {
  description = "Name of the S3 bucket to create, for example \"acme-faber-content\". Bucket names are global and can't be changed later. With access logging on, a second bucket with the same name plus \"-logs\" holds the trail."
  type        = string

  validation {
    condition = (
      can(regex("^[a-z0-9][a-z0-9-]{1,56}[a-z0-9]$", var.bucket_name)) &&
      !strcontains(var.bucket_name, "--") &&
      !startswith(var.bucket_name, "xn--") &&
      !startswith(var.bucket_name, "sthree-") &&
      !startswith(var.bucket_name, "amzn-s3-demo-") &&
      !endswith(var.bucket_name, "-s3alias") &&
      !endswith(var.bucket_name, "--ol-s3") &&
      !endswith(var.bucket_name, "--x-s3") &&
      !endswith(var.bucket_name, "--table-s3")
    )
    error_message = "bucket_name must be 3-58 characters of lowercase letters, digits or dashes, start and end with a letter or digit, have no double dashes, and not use a prefix or suffix S3 reserves (such as \"xn--\" or \"-s3alias\"). The limit is 58 so the \"-logs\" bucket name still fits."
  }
}

variable "faber_service_account" {
  description = "The Faber service account for your workspace. Faber sends you this value; it looks like faber-ws-acme@project-54fc229c-12bb-4421-919.iam.gserviceaccount.com."
  type        = string

  validation {
    condition     = can(regex("^faber-ws-[a-z0-9-]*[a-z0-9]@project-54fc229c-12bb-4421-919\\.iam\\.gserviceaccount\\.com$", var.faber_service_account))
    error_message = "faber_service_account must be the Faber workspace service account Faber sent you: faber-ws-<your-company>@project-54fc229c-12bb-4421-919.iam.gserviceaccount.com."
  }
}

variable "faber_service_account_id" {
  description = "The numeric ID (uniqueId) of the Faber service account. Faber sends you this value with the email. The role trusts Google sign-in tokens for this ID only."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{21}$", var.faber_service_account_id))
    error_message = "faber_service_account_id must be the 21-digit numeric ID Faber sent you."
  }
}

variable "faber_access_enabled" {
  description = "Let Faber's service account assume the Faber role. Set to false and apply to cut Faber off: this deletes the role, so Faber can no longer reach the bucket or the key. Set back to true to restore access."
  type        = bool
  default     = true
}

variable "enable_bedrock" {
  description = "Let the Faber role call Anthropic's Claude models on Amazon Bedrock in this account. Leave false to skip AI features."
  type        = bool
  default     = false
}

variable "enable_access_logging" {
  description = "Create a CloudTrail trail that records the account's management events (including every use of the key) and every object-level read and write on the bucket, into a separate private log bucket. Set to false if an organization trail already covers this account and you'll add a data-event selector for the bucket to it."
  type        = bool
  default     = true
}

variable "role_name" {
  description = "Name of the IAM role Faber assumes."
  type        = string
  default     = "faber-access"

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.role_name))
    error_message = "role_name must be 1-64 characters of letters, digits or +=,.@_-."
  }
}

variable "role_permissions_boundary" {
  description = "ARN of a permissions boundary to attach to the Faber role, if your account requires one for new roles."
  type        = string
  default     = null

  validation {
    condition     = var.role_permissions_boundary == null || can(regex("^arn:aws[a-z-]*:iam::([0-9]{12}|aws):policy/.+$", var.role_permissions_boundary))
    error_message = "role_permissions_boundary must be an IAM policy ARN."
  }
}

variable "key_rotation_days" {
  description = "How often AWS KMS rotates the key, in days (90-2560). Defaults to 90 days."
  type        = number
  default     = 90

  validation {
    condition     = var.key_rotation_days >= 90 && var.key_rotation_days <= 2560 && floor(var.key_rotation_days) == var.key_rotation_days
    error_message = "key_rotation_days must be a whole number from 90 to 2560."
  }
}

variable "noncurrent_version_retention_days" {
  description = "Days to keep an object's previous versions after it's overwritten or deleted. Versions beyond the 4 most recent previous ones are also removed after a day."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_version_retention_days >= 1 && floor(var.noncurrent_version_retention_days) == var.noncurrent_version_retention_days
    error_message = "noncurrent_version_retention_days must be a whole number of at least 1."
  }
}

variable "log_retention_days" {
  description = "Days to keep CloudTrail log files in the log bucket. Only used when enable_access_logging is true."
  type        = number
  default     = 365

  validation {
    condition     = var.log_retention_days >= 1 && floor(var.log_retention_days) == var.log_retention_days
    error_message = "log_retention_days must be a whole number of at least 1."
  }
}

variable "tags" {
  description = "Extra tags for everything the module creates. A managed-by = \"faber-terraform\" tag is always added."
  type        = map(string)
  default     = {}
}
