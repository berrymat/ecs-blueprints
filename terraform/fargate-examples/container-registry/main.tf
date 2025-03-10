terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

################################################################################
# ECR Repository
################################################################################
resource "aws_ecr_repository" "this" {
  name         = "portal-api"
  force_delete = false #Change this to true to delete non empty repositories

  image_tag_mutability = "MUTABLE"
  tags = {
    Name = "Portal API Repo"
  }
}
