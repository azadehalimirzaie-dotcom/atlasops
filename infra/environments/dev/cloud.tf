# Require a compatible Terraform CLI and store state in the named HCP Terraform workspace.
terraform {
  required_version = ">= 1.16.0, < 2.0.0"

  # Authenticate with terraform login before initializing this remote workspace.
  cloud {
    organization = "learning_terraform_Project"

    workspaces {
      name = "atlasops-dev"
    }
  }
}