# Define AWS service roles, controller roles, and the policies required by the EKS cluster.
# IAM role used by the EKS service to manage the cluster's AWS resources.
# The EKS module in main.tf uses this role as its control-plane role.
resource "aws_iam_role" "eks_cluster" {
  name = "${var.resource_tags["Project"]}-${var.resource_tags["Environment"]}-eks-cluster"

  # Trust policy: allows the EKS service to assume this role.
  # Permissions for actions taken with the role are attached separately below.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.resource_tags
}

# Attach the AWS-managed cluster policy to the control-plane role.
# It grants EKS permissions to manage supporting AWS resources for the cluster.
resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# IAM role intended for EC2 instances that run Kubernetes worker nodes.
# Creating the role alone does not assign it to instances; a node group or
# instance profile must use it when worker nodes are provisioned.
resource "aws_iam_role" "eks_nodes" {
  name = "${var.resource_tags["Project"]}-${var.resource_tags["Environment"]}-eks-nodes"

  # Trust policy: allows the EC2 service to assume this role for worker instances.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.resource_tags
}

# Attach the AWS-managed worker-node policy to the node role.
# It allows nodes to discover cluster and EC2 information needed to operate.
resource "aws_iam_role_policy_attachment" "eks_nodes" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# Allow worker nodes to authenticate to Amazon ECR and pull container images.
# This AWS-managed policy does not grant image push permissions.
resource "aws_iam_role_policy_attachment" "eks_ecr_pull" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}
# Allow the Amazon VPC CNI plugin (aws-node) to manage network interfaces and
# VPC IP addresses for pods. Here the policy is attached to the node role, so
# aws-node relies on node credentials rather than a dedicated IAM role.
resource "aws_iam_role_policy_attachment" "eks_cni" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Allow the SSM Agent on worker nodes to communicate with Systems Manager.
# Supports node management and Session Manager access when the agent is running
# and the nodes can reach the required Systems Manager endpoints.
resource "aws_iam_role_policy_attachment" "eks_ssm" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Pass the role ARNs on only after all policies are attached
resource "terraform_data" "eks_cluster_role" {
  input      = aws_iam_role.eks_cluster.arn
  depends_on = [aws_iam_role_policy_attachment.eks_cluster]
}

# Delay passing the node role to EKS until every required node policy has been attached.
resource "terraform_data" "eks_node_role" {
  input = aws_iam_role.eks_nodes.arn
  depends_on = [
    aws_iam_role_policy_attachment.eks_nodes,
    aws_iam_role_policy_attachment.eks_cni,
    aws_iam_role_policy_attachment.eks_ecr_pull,
    aws_iam_role_policy_attachment.eks_ssm,
  ]
}
##########################
#load-balancer_controller
##########################
# IRSA trust-policy structure for the Load Balancer Controller. It allows the Kubernetes service account named aws-load-balancer-controller in namespace kube-system to assume this role.
resource "aws_iam_role" "lb_controller" {
  name = "${var.resource_tags["Project"]}-${var.resource_tags["Environment"]}-lb-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn # trust tokens from this Kubernetes cluster
      }
      Action = "sts:AssumeRoleWithWebIdentity" # exchange that token for credentials
      Condition = {
        StringEquals = {
          "${module.eks.oidc_provider}:aud" = "sts.amazonaws.com"
          "${module.eks.oidc_provider}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })

  tags = var.resource_tags
}

# Load controller permissions from the checked-in policy JSON; no permissions are embedded here.
resource "aws_iam_policy" "lb_controller" {
  name = "${var.resource_tags["Project"]}-${var.resource_tags["Environment"]}-lb-controller"
  policy = file("${path.module}/policies/aws-loadbalancer-controller.json")
  tags = var.resource_tags
}
# Attach the load-balancer permissions to the controller role used by its service account.
resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller.arn
}

##########################################
#EBS_CSI
##########################################
# Intended role for the EBS CSI controller, which provisions and attaches EBS volumes.
resource "aws_iam_role" "ebs_csi" {
  name = "${var.resource_tags["Project"]}-${var.resource_tags["Environment"]}-ebs-csi"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"

      Condition = {
        StringEquals = {
          "${module.eks.oidc_provider}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          "${module.eks.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.resource_tags
}
# Grant the storage controller AWS-managed permissions for EBS volume operations.
resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicyV2"
}
