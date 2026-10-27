# The same setup with AI features on: the Faber role can call Anthropic's Claude
# models on Amazon Bedrock in this account.

provider "aws" {
  region = "us-east-2"
}

module "faber" {
  source = "../.."

  bucket_name              = "acme-faber-content"
  faber_service_account    = "faber-ws-acme@project-54fc229c-12bb-4421-919.iam.gserviceaccount.com"
  faber_service_account_id = "123456789012345678901"
  enable_bedrock           = true
}

output "faber_handoff" {
  value = module.faber.handoff
}
