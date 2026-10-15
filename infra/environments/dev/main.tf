# Discover available Availability Zones in the configured AWS region.
data "aws_availability_zones" "available" {
  state = "available"
}


# Create the VPC and its public/private subnets for the EKS cluster and nodes.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7.3"
  name    = "${var.resource_tags["Project"]}-${var.resource_tags["Environment"]}-vpc"
  cidr    = var.vpc_cidr_block

  # Select the requested number of zones and subnet CIDRs from the input lists.
  azs             = slice(data.aws_availability_zones.available.names, 0, var.number_of_availability_zones)
  private_subnets = slice(var.private_subnets_cidr_blocks, 0, var.private_subnets_count)
  public_subnets  = slice(var.public_subnets_cidr_blocks, 0, var.public_subnets_count)

  # Enable outbound internet access from private subnets through NAT gateways.
  # The two input flags control whether gateways are shared or created per AZ.
  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = var.one_nat_gateway_per_az
  # Do not create a virtual private gateway for a site-to-site VPN.
  enable_vpn_gateway   = false
  create_igw           = true
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = var.resource_tags
}


# Create the EKS control plane and the managed worker-node group below.
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = "${var.resource_tags["Project"]}-${var.resource_tags["Environment"]}-eks"
  kubernetes_version = "1.36"

  # Allow API access within the VPC and through the public endpoint.
  # Restrict public access to the configured IPv4 CIDR (use /32 for one address).
  endpoint_private_access      = true
  endpoint_public_access       = true
  endpoint_public_access_cidrs = [var.my_public_ipv4]

  # Grant the IAM identity running Terraform cluster-admin access via an EKS access entry.
  enable_cluster_creator_admin_permissions = true

  # Disable EKS Auto Mode; worker capacity is provided by the managed node group below.
  compute_config = {
    enabled = false
  }

  # Place cluster network interfaces in the VPC's private subnets.
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Support IAM authentication through both EKS access entries and the aws-auth ConfigMap.
  authentication_mode = "API_AND_CONFIG_MAP"

  # Use the control-plane IAM role defined in iam.tf instead of creating another role.
  create_iam_role = false
  iam_role_arn    = terraform_data.eks_cluster_role.output
  enable_irsa     = true


  # Configure the module-created worker-node security group.
  # Recommended rules include node-to-node ephemeral TCP ports and all outbound traffic.
  # Using a name prefix lets Terraform append a unique suffix to the group name.
  node_security_group_description              = "Security group for EKS worker nodes"
  node_security_group_enable_recommended_rules = true
  node_security_group_use_name_prefix          = true
  node_security_group_additional_rules = {
    ingress_http_between_nodes = {
      description = "Allow HTTP between worker nodes and their pods"
      protocol    = "tcp"
      from_port   = 80
      to_port     = 80
      type        = "ingress"
      self        = true
    }
  }
  # Do not configure a customer-managed KMS key or its IAM policy through this module.
  # This leaves EKS service-managed encryption defaults in place.
  create_kms_key           = false
  encryption_config        = null
  attach_encryption_policy = false

  # Module v21 does not install the default networking add-ons automatically.
  # Install VPC CNI before nodes so they can initialize pod networking and become Ready.
  # CoreDNS provides cluster DNS; kube-proxy implements Kubernetes Service networking.
  addons = {
    vpc-cni = {
      before_compute = true
    }
    kube-proxy = {}
    coredns    = {}
  }

  # Create an EKS managed node group in the private subnets configured above.
  eks_managed_node_groups = {
    worker_nodes = {
      # Use the standard Amazon Linux 2023 EKS AMI for x86-64 instances.
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.medium"]
      # Start with two nodes; allow the group size to range from two to three.
      # These limits do not deploy a Kubernetes autoscaler.
      desired_size = 2
      max_size     = 3
      min_size     = 2

      # Provision On-Demand instances; SPOT is the alternative capacity type.
      capacity_type = "ON_DEMAND"


      # Rely on EKS-managed AMI bootstrapping instead of injecting custom bootstrap data.
      enable_bootstrap_user_data = false


      # Reuse the worker-node IAM role and its policy attachments from iam.tf.
      create_iam_role = false
      iam_role_arn    = terraform_data.eks_node_role.output


      # Kubernetes node labels for selecting nodes in workload scheduling rules.
      labels = {
        Environment = var.resource_tags["Environment"]
        workload    = "general"
      }

      tags = var.resource_tags
    }
  }

  tags = var.resource_tags
}
