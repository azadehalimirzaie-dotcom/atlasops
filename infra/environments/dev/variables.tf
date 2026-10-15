#######################
#VPC
########################
variable "region" {
  description = "The AWS region to deploy the VPC"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr_block" {
  description = "The CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}
variable "number_of_availability_zones" {
  description = "The number of availability zones for the VPC"
  type        = number
  default     = 2
}
variable "private_subnets_count" {
  description = "The number of private subnets for the VPC"
  type        = number
  default     = 2
}
variable "private_subnets_cidr_blocks" {
  description = "The CIDR blocks for the private subnets"
  type        = list(string)
  default = ["10.20.11.0/24",
    "10.20.12.0/24",
    "10.20.13.0/24",
    "10.20.14.0/24",
  "10.20.15.0/24"]
}
variable "public_subnets_count" {
  description = "The number of public subnets for the VPC"
  type        = number
  default     = 2
}
variable "public_subnets_cidr_blocks" {
  description = "The CIDR blocks for the public subnets"
  type        = list(string)
  default = ["10.20.1.0/24",
    "10.20.2.0/24",
    "10.20.3.0/24",
    "10.20.4.0/24",
  "10.20.5.0/24"]
}
variable "enable_nat_gateway" {
  description = "Whether to enable NAT gateway for the VPC"
  type        = bool
  default     = true
}
variable "single_nat_gateway" {
  description = "Whether to use a single NAT gateway for the VPC"
  type        = bool
  default     = true
}
variable "one_nat_gateway_per_az" {
  description = "Whether to use one NAT gateway per availability zone for the VPC"
  type        = bool
  default     = false
}
variable "enable_vpn_gateway" {
  description = "Whether to enable VPN gateway for the VPC"
  type        = bool
  default     = false
}
variable "resource_tags" {
  description = "A map of tags to assign to the VPC and its resources"
  type        = map(string)
  default = {
    Project     = "AtlasOps"
    Environment = "dev"
    Owner       = "Azadeh"
    ManagedBy   = "Terraform"
    CostCenter  = "NeueFischer"
  }
}

variable "my_public_ipv4" {
  description = "The public IPv4 address for my local machine to allow access to the VPC"
  type        = string
  default     = "46.128.143.64/32"
}
##########################
#ECR
##########################
variable "encryption_type" {
  description = "The encryption type for the ECR repository"
  type        = string
  default     = "AES256"
}

variable "image_scan_on_push" {
  description = "Whether to enable image scanning on push for the ECR repository"
  type        = bool
  default     = true
}

variable "image_tag_mutability" {
  description = "The image tag mutability setting for the ECR repository"
  type        = string
  default     = "IMMUTABLE"
}
###########################
#SNS_topic
###########################
variable "alert_emails" {
  description = "Email address that receives AtlasOps alerts."
  type        = map(string)
}