# Select the AWS provider version and configure the account and region used by all AWS resources.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  # Account guard: fail rather than accidentally provisioning resources in another account.
  allowed_account_ids = ["483598626808"]

}