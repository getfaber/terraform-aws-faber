# Security

## Reporting a problem

Please report security problems with this module through GitHub:

- If **private vulnerability reporting** is available on this repository (Security tab → "Report a vulnerability"), use it, so the details stay private until a fix is out.
- Otherwise, [open an issue](https://github.com/getfaber/terraform-aws-faber/issues/new/choose) that says you have a security report, **without the details**, and we'll arrange a private way to share them.

Please don't put credentials, account IDs, ARNs or other details of your own environment in public issues.

## What this module grants

The Faber role can be assumed only with a Google ID token for your Faber workspace's service account, with audience `sts.amazonaws.com`. It gets `s3:ListBucket` on the bucket, `s3:GetObject`, `s3:PutObject` and `s3:DeleteObject` on its objects, and `kms:Decrypt` and `kms:GenerateDataKey` on the key through S3 only. With `enable_bedrock = true` it can also invoke Anthropic models on Amazon Bedrock. It gets no IAM permissions, no bucket settings and no access keys. See the [README](https://github.com/getfaber/terraform-aws-faber/blob/main/README.md) for details.
