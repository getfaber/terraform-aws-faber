locals {
  module_version = "1.0.0" # x-release-please-version

  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  dns_suffix = data.aws_partition.current.dns_suffix
  # aws 6.x renamed the region's "name" to "region" and deprecated "name";
  # lookup reads whichever exists without a deprecation warning.
  region = lookup(data.aws_region.current, "region", lookup(data.aws_region.current, "name", null))

  tags = merge(var.tags, {
    managed-by = "faber-terraform"
  })

  log_bucket_name = "${var.bucket_name}-logs"
  trail_name      = "faber-${var.bucket_name}"

  # Built rather than read from the trail, because the key policy and the log
  # bucket policy both have to exist before the trail can be created.
  trail_arn = "arn:${local.partition}:cloudtrail:${local.region}:${local.account_id}:trail/${local.trail_name}"
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}
