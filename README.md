# terraform-aws-faber

Terraform module that sets up an AWS account to hold your [Faber](https://www.getfaber.app) content. Everything your team publishes in Faber is stored in a bucket you own, encrypted with a key you own. Faber's database keeps only account details such as names, emails and permissions.

The module creates:

- a private, versioned **S3 bucket** encrypted with your key, with all public access blocked, TLS required, and uploads that ask for any other key refused
- an **AWS KMS key** that rotates every 90 days
- an **IAM role** that only your Faber workspace's service account can assume, with read, write and delete access to objects in that bucket and nothing else
- a **CloudTrail trail** that records every read and write on the bucket and every use of the key, in a separate private log bucket (optional, on by default)
- **Amazon Bedrock** access to Anthropic's Claude models for the same role, so prompts stay in your account (optional, off by default)

Nothing runs in your account, and Faber holds no AWS credentials. Faber signs in with a short-lived Google ID token for your workspace's service account, which only this role trusts.

## Usage

```hcl
provider "aws" {
  region = "us-east-2"
}

module "faber" {
  source  = "getfaber/faber/aws"
  version = "~> 1.0"

  bucket_name              = "<your-company>-faber-content"
  faber_service_account    = "faber-ws-<your-company>@project-54fc229c-12bb-4421-919.iam.gserviceaccount.com"
  faber_service_account_id = "<21-digit ID Faber sends you>"

  # enable_bedrock = true # optional: turn on AI features
}

output "faber_handoff" {
  value = module.faber.handoff
}
```

Faber sends you the exact `faber_service_account` and `faber_service_account_id` values for your workspace. The module uses the region of the `aws` provider it's given, so leave out the `provider` block if your configuration already has one for the region you want. Faber runs in the US, and us-east-2 (Ohio) is the closest AWS region.

After `terraform apply`, run `terraform output faber_handoff` and send the result to Faber. None of it is secret. Faber needs `bucket_name`, `region`, `role_arn` and `kms_key_arn`; the rest helps us check the setup.

See [`examples/`](https://github.com/getfaber/terraform-aws-faber/tree/main/examples) for complete configurations.

## Before you apply

- **Use an account just for Faber if you can.** The trail records the whole account's management events, in every region, as well as the bucket's object-level events.
  - The first trail in an account records management events for free. A second copy, for example if you already have a trail, costs about $2 per 100,000 events.
  - Object-level events on the bucket cost about $0.10 per 100,000.
  - The KMS key costs $1 a month, plus $1 a month for each of its first two rotations, so about $3 a month after six months with 90-day rotation.
  - If an organization trail already covers the account, set `enable_access_logging = false` and add a data-event selector for `arn:aws:s3:::<bucket_name>/` to that trail.
- **Service control policies.** If your organization uses them, make sure they allow `sts:AssumeRoleWithWebIdentity` for the Faber role, S3 and KMS on the bucket and key, and Bedrock if you turn it on.
- **Permissions boundaries.** If new roles in your account need one, set `role_permissions_boundary`. The boundary must allow everything the role's policy grants.
- **Claude on Amazon Bedrock.** Before you turn AI on, have an admin open each Claude model Faber uses in the Bedrock console playground and run it once. The first use of an Anthropic model in an account needs a one-time use-case form and an AWS Marketplace subscription, which the Faber role isn't allowed to start. Faber calls Claude through cross-region inference profiles, so the role can invoke the models in any region a profile routes to.
- **Names are permanent.** Bucket names are global and fixed. With access logging on, the module also creates `<bucket_name>-logs`, so `bucket_name` can be at most 58 characters.
- **Who runs it.** Whoever applies the module needs rights to manage S3 buckets and their policies, KMS keys, IAM roles and CloudTrail trails, for example `AdministratorAccess` in the account.

## Cutting off Faber's access

Set `faber_access_enabled = false` and apply. This deletes the Faber role, so within a few minutes content, lists and search stop loading in Faber, though people can still sign in. Set it back to `true` to restore access; the role comes back with the same ARN.

You can also disable the KMS key, which locks you out of the content too until you turn it back on. Your next `terraform apply` turns a disabled key back on, so `faber_access_enabled` is the switch that sticks.

## Safety

- The bucket and key have `prevent_destroy`, and the bucket has `force_destroy = false`. `terraform destroy` stops with an error instead of removing them. To really remove them, take them out of state or delete the `lifecycle` blocks in your own copy.
- **Scheduling the key for deletion makes the data unreadable once the 30-day waiting period ends, for you as well as for Faber.**
- Old object versions are kept for `noncurrent_version_retention_days` (30 by default). Once an object has more than 4 previous versions, the extra older ones are removed after a day.
- Uploads that ask for SSE-S3, another KMS key, or the AWS managed `aws/s3` key are refused, so everything in the bucket is encrypted with your key. Uploads that send no encryption headers get your key by default.
- The log bucket also has `force_destroy = false`, so turning access logging off later fails while the bucket still holds logs. Empty it first, or keep it by removing `module.faber.aws_s3_bucket.logs[0]` and its settings from state.
- Check with Faber before you change the bucket's permissions or lifecycle rules, move or rename it, or disable or delete the key.

## How Faber signs in

AWS trusts Google as a built-in identity provider, so there's no identity provider to create and no AWS credentials to hand over. The role's trust policy allows `sts:AssumeRoleWithWebIdentity` only for Google ID tokens that meet all of these:

| Condition key | Token claim | Required value |
|---|---|---|
| `accounts.google.com:sub` | `sub` | your workspace service account's numeric ID |
| `accounts.google.com:aud` | `azp` | the same ID, so only that service account can request the token |
| `accounts.google.com:oaud` | `aud` | `sts.amazonaws.com` |

Sessions last at most an hour. The role can use the key only through S3 in the bucket's region (`kms:ViaService`), and the key policy leaves all key use to IAM policies in your account.

## Requirements

| Tool | Version |
|---|---|
| Terraform | >= 1.5 |
| OpenTofu | >= 1.6 |
| `hashicorp/aws` provider | >= 5.49, < 7.0 |

## Troubleshooting

- **`BucketAlreadyExists`**: another AWS account already uses that bucket name. Pick a different `bucket_name`.
- **`AccessDenied` creating the role or its policy**: a service control policy or a required permissions boundary is blocking it. See "Before you apply".
- **`InsufficientS3BucketPolicyException` creating the trail** on the first apply: S3 hasn't finished applying the log bucket policy yet. Wait a minute and run `terraform apply` again.
- **`AccessDeniedException` from Bedrock in Faber** right after you turn AI on: the model hasn't been used in your account yet. Run it once in the Bedrock console playground. See "Before you apply".
- **`Instance cannot be destroyed`**: that's `prevent_destroy` protecting the bucket and key. See Safety.

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
|------|------|
| [aws_cloudtrail.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudtrail) | resource |
| [aws_iam_role.faber](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.faber](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_s3_bucket.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_lifecycle_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_ownership_controls.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_ownership_controls.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_s3_bucket_versioning.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| bucket_name | Name of the S3 bucket to create, for example "acme-faber-content". Bucket names are global and can't be changed later. With access logging on, a second bucket with the same name plus "-logs" holds the trail. | `string` | n/a | yes |
| enable_access_logging | Create a CloudTrail trail that records the account's management events (including every use of the key) and every object-level read and write on the bucket, into a separate private log bucket. Set to false if an organization trail already covers this account and you'll add a data-event selector for the bucket to it. | `bool` | `true` | no |
| enable_bedrock | Let the Faber role call Anthropic's Claude models on Amazon Bedrock in this account. Leave false to skip AI features. | `bool` | `false` | no |
| faber_access_enabled | Let Faber's service account assume the Faber role. Set to false and apply to cut Faber off: this deletes the role, so Faber can no longer reach the bucket or the key. Set back to true to restore access. | `bool` | `true` | no |
| faber_service_account | The Faber service account for your workspace. Faber sends you this value; it looks like faber-ws-acme@project-54fc229c-12bb-4421-919.iam.gserviceaccount.com. | `string` | n/a | yes |
| faber_service_account_id | The numeric ID (uniqueId) of the Faber service account. Faber sends you this value with the email. The role trusts Google sign-in tokens for this ID only. | `string` | n/a | yes |
| key_rotation_days | How often AWS KMS rotates the key, in days (90-2560). Defaults to 90 days. | `number` | `90` | no |
| log_retention_days | Days to keep CloudTrail log files in the log bucket. Only used when enable_access_logging is true. | `number` | `365` | no |
| noncurrent_version_retention_days | Days to keep an object's previous versions after it's overwritten or deleted. Versions beyond the 4 most recent previous ones are also removed after a day. | `number` | `30` | no |
| role_name | Name of the IAM role Faber assumes. | `string` | `"faber-access"` | no |
| role_permissions_boundary | ARN of a permissions boundary to attach to the Faber role, if your account requires one for new roles. | `string` | `null` | no |
| tags | Extra tags for everything the module creates. A managed-by = "faber-terraform" tag is always added. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| bucket_name | Name of the bucket that holds your Faber content. |
| handoff | Values to send to Faber once the apply finishes. None of them are secret. |
| kms_key_arn | ARN of the AWS KMS key that encrypts the bucket. |
| log_bucket_name | Name of the bucket that holds the CloudTrail logs, or null when access logging is off. |
| role_arn | ARN of the role Faber assumes, or null while faber_access_enabled is false. |
<!-- END_TF_DOCS -->

## Support

Questions, problems or ideas: please [open an issue](https://github.com/getfaber/terraform-aws-faber/issues). For security reports, see [SECURITY.md](https://github.com/getfaber/terraform-aws-faber/blob/main/SECURITY.md).

## License

[Apache 2.0](https://github.com/getfaber/terraform-aws-faber/blob/main/LICENSE)
