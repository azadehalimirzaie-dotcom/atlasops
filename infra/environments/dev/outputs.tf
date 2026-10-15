#########################
#VPC
########################

output "region" {
  description = "The AWS region"
  value       = var.region
}
output "availability_zones" {
  description = "The availability zones"
  value       = module.vpc.azs
}
output "account_id" {
  description = "The AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}
output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = var.vpc_cidr_block
}
output "public_subnet_ids" {
  description = "The IDs of the public subnets"
  value       = module.vpc.public_subnets
}
output "private_subnet_ids" {
  description = "The IDs of the private subnets"
  value       = module.vpc.private_subnets
}
output "nat_gateway_ids" {
  description = "The IDs of the NAT gateways"
  value       = module.vpc.natgw_ids
}
output "public_route_table_ids" {
  description = "The IDs of the public route tables"
  value       = module.vpc.public_route_table_ids
}
output "private_route_table_ids" {
  description = "The IDs of the private route tables"
  value       = module.vpc.private_route_table_ids
}
output "igw_id" {
  description = "The ID of the internet gateway"
  value       = module.vpc.igw_id
}

###########################
#EKS
###########################

output "eks_cluster_role_arn" {
  description = "IAM role for the EKS control plane."
  value       = aws_iam_role.eks_cluster.arn
}

output "eks_node_role_arn" {
  description = "IAM role for EKS worker nodes."
  value       = aws_iam_role.eks_nodes.arn
}

output "eks_cluster_endpoint" {
  description = "The endpoint of the EKS cluster."
  value       = module.eks.cluster_endpoint
}
output "cluster_arn" {
  description = "The ARN of the EKS cluster."
  value       = module.eks.cluster_arn
}
output "cluster_name" {
  description = "The name of the EKS cluster."
  value       = module.eks.cluster_name
}
output "cluster_status" {
  description = "The status of the EKS cluster."
  value       = module.eks.cluster_status
}
output "cluster_version" {
  description = "The version of the EKS cluster."
  value       = module.eks.cluster_version
}

output "nodegroup_arn" {
  description = "The ARN of the EKS node group."
  value       = module.eks.eks_managed_node_groups["worker_nodes"].node_group_arn
}

output "nodegroup_id" {
  description = "The ID of the EKS node group."
  value       = module.eks.eks_managed_node_groups["worker_nodes"].node_group_id
}
output "nodegroup_status" {
  description = "The status of the EKS node group."
  value       = module.eks.eks_managed_node_groups["worker_nodes"].node_group_status
}

#########################
#ECR
########################
output "ecr_repository_urls" {
  description = "Repository URLs used to tag and push container images."
  value = {
    for name, repo in module.ecr : name => repo.repository_url
  }
}
#########################
#SQS
########################
output "sqs_queue_url" {
  description = "URL used by ingestion and worker applications."
  value       = module.sqs.queue_url
}

output "sqs_queue_arn" {
  description = "ARN used in IAM policies for the events queue."
  value       = module.sqs.queue_arn
}

output "sqs_dlq_url" {
  description = "URL used to inspect messages in the dead-letter queue."
  value       = module.sqs.dead_letter_queue_url
}

output "sqs_dlq_arn" {
  description = "ARN of the dead-letter queue."
  value       = module.sqs.dead_letter_queue_arn
}

######################
#Dynamodb
######################
output "dynamodb_table_name" {
  description = "Name of the DynamoDB table."
  value       = module.dynamodb_table.table_name
}
output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table."
  value       = module.dynamodb_table.table_arn
}

#####################
#Application Roles
#####################

output "ingestion_role_arn" {
  description = "IAM role used by the ingestion Kubernetes service account."
  value       = aws_iam_role.application["ingestion"].arn
}

output "worker_role_arn" {
  description = "IAM role used by the worker Kubernetes service account."
  value       = aws_iam_role.application["worker"].arn
}

######################
#SNS
######################
output "sns_topic_arn" {
  description = "ARN of the SNS topic."
  value       = module.sns_topic.topic_arn
}
output "subscriptions" {
  description = "Map of subscriptions created and their attributes"
  value       = module.sns_topic.subscriptions
}

#####################
#Github_actions
####################
output "github_actions_role_arn" {
  description = "IAM role assumed by GitHub Actions to push AtlasOps images."
  value       = aws_iam_role.github_actions.arn
}