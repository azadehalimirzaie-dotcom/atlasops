terraform {
  required_version = ">= 1.16.0, < 2.0.0"

  cloud {
    organization = "learning_terraform_Project"

    workspaces {
      name = "atlasops-dev"
    }
  }
}