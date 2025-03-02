terraform {
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.dev_region
  alias  = "dev"
}

#provider "aws" {
#  region = var.prod_region
#  alias = "prod"
#}

module "state_management" {
  source = "./state-management"
}

module "container_registry" {
  source = "./container-registry"
  providers = {
    aws = aws.dev
  }
}

module "core_infra_dev" {
  source = "./core-infra"
  region = var.dev_region
  providers = {
    aws = aws.dev
  }
  name = "${var.name}-dev"
}

#module "core_infra_prod" {
#  source = "./core-infra"
#  region = var.prod_region
#  providers = {
#    aws = aws.prod
#  }
#  name = "${var.name}-prod"
#}

module "lb_service_dev" {
  source = "./lb-service"
  providers = {
    aws = aws.dev
  }
  ecr_repository_url             = module.container_registry.ecr_repository_url
  cluster_arn                    = module.core_infra_dev.cluster_arn
  service_discovery_namespace_id = module.core_infra_dev.service_discovery_namespace_id
  vpc_id                         = module.core_infra_dev.vpc_id
  public_subnets                 = module.core_infra_dev.public_subnets
  private_subnets                = module.core_infra_dev.private_subnets
  private_subnet_objects         = module.core_infra_dev.private_subnet_objects
}

module "api_gateway_dev" {
  source     = "./api-gateway"
  name       = "${var.name}-dev"
  region     = var.dev_region
  stage_name = "dev"
  providers = {
    aws = aws.dev
  }
}

#module "lb_service_prod" {
#  source                         = "./lb-service"
#  providers = {
#    aws = aws.prod
#  }
#  ecr_repository_url             = module.container_registry.ecr_repository_url
#  cluster_arn                    = module.core_infra_prod.cluster_arn
#  service_discovery_namespace_id = module.core_infra_prod.service_discovery_namespace_id
#  vpc_id                         = module.core_infra_prod.vpc_id
#  public_subnets                 = module.core_infra_prod.public_subnets
#  private_subnets                = module.core_infra_prod.private_subnets
#  private_subnet_objects         = module.core_infra_prod.private_subnet_objects
#}

#module "api_gateway_prod" {
#  source = "./api-gateway"
#  name   = "${var.name}-prod"
#  region = var.prod_region
#  stage_name = "prod"
#  providers = {
#    aws = aws.prod
#  }
#}
