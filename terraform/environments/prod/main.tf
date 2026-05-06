terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state in S3 — create the bucket manually before first apply
  backend "s3" {
    bucket         = "damolak-terraform-state-775143001467"
    key            = "prod/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "damolak-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
    Team        = "DevOps"
  }
}

#  Data Sources 
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

#  Modules 
module "vpc" {
  source = "../../modules/vpc"

  project            = var.project
  vpc_cidr           = var.vpc_cidr
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)
  app_port           = var.app_port
  tags               = local.common_tags
}

module "ecr" {
  source          = "../../modules/ecr"
  repository_name = var.project
  tags            = local.common_tags
}

module "ecs" {
  source = "../../modules/ecs"

  project                     = var.project
  environment                 = var.environment
  aws_region                  = var.aws_region
  vpc_id                      = module.vpc.vpc_id
  public_subnet_ids           = module.vpc.public_subnet_ids
  private_subnet_ids          = module.vpc.private_subnet_ids
  alb_security_group_id       = module.vpc.alb_security_group_id
  ecs_tasks_security_group_id = module.vpc.ecs_tasks_security_group_id
  container_image             = "${module.ecr.repository_url}:${var.image_tag}"
  app_version                 = var.image_tag
  app_port                    = var.app_port
  task_cpu                    = var.task_cpu
  task_memory                 = var.task_memory
  desired_count               = var.desired_count
  min_capacity                = var.min_capacity
  max_capacity                = var.max_capacity
  tags                        = local.common_tags
}

module "monitoring" {
  source = "../../modules/monitoring"

  project                  = var.project
  aws_region               = var.aws_region
  cluster_name             = module.ecs.cluster_name
  service_name             = module.ecs.service_name
  log_group_name           = module.ecs.log_group_name
  alb_arn_suffix           = module.ecs.alb_arn_suffix
  target_group_arn_suffix  = module.ecs.target_group_arn_suffix
  alert_email              = var.alert_email
  tags                     = local.common_tags
}
