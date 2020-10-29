terraform {
  required_version = ">= 0.12.6"
}

provider "aws" {
  version = ">= 2.28.1"
  region  = var.region
  profile = "cicd"
}

provider "random" {
  version = "~> 2.1"
}

provider "local" {
  version = "~> 1.2"
}

provider "null" {
  version = "~> 2.1"
}

provider "template" {
  version = "~> 2.1"
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
  version                = "~> 1.11"
}

data "aws_availability_zones" "available" {
}

locals {
  cluster_name = "test-eks"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.47.0"

  name                 = "test-vpc"
  cidr                 = "172.16.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = ["172.16.1.0/24", "172.16.2.0/24", "172.16.3.0/24"]
  public_subnets       = ["172.16.4.0/24", "172.16.5.0/24", "172.16.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

}
module "security_group" {
  source = "git@github.com:youse-seguradora/terraform-aws-security-group.git"

  name        = "test-sg"
  description = "security group"
  vpc_id      = module.vpc.vpc_id


  ingress_with_cidr_blocks = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "Service name"
      cidr_blocks = "10.0.0.0/8"
    },
  ]

  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = -1
      description = "Allow cluster egress access to the Internet."
      cidr_blocks = "0.0.0.0/0"
    },
  ]

  tags = {
    Service     = "test-basic"
    Managed_by  = "Terraform"
    Environment = "test"
  }

}

module "eks" {
  source          = "../.."
  cluster_name    = local.cluster_name
  cluster_version = "1.17"
  subnets         = module.vpc.private_subnets

  tags = {
    Environment = "test"
    GithubRepo  = "terraform-aws-eks"
    GithubOrg   = "terraform-aws-modules"
  }

  vpc_id = module.vpc.vpc_id

  # manage_aws_auth = false

  node_groups_defaults = {
    ami_type  = "AL2_x86_64"
    disk_size = 20
  }

  node_groups = {
    example = {
      node_group_name  = "test"
      desired_capacity = 1
      max_capacity     = 10
      min_capacity     = 1

      instance_type = "m5.large"
      k8s_labels = {
        Environment = "test"
        GithubRepo  = "terraform-aws-eks"
        GithubOrg   = "terraform-aws-modules"
      }
      additional_tags = {
        ExtraTag = "example"
      }
    }
  }
}
