# Expose the authenticated AWS account and principal for checking which identity Terraform uses.
data "aws_caller_identity" "current" {}

output "aws_account_id" {
  description = "AWS account used by this Terraform run."
  value       = data.aws_caller_identity.current.account_id
}

output "aws_identity_arn" {
  description = "AWS identity used by this Terraform run."
  value       = data.aws_caller_identity.current.arn
}