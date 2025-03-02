terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  region = var.region
}

################################################################################
# API Gateway
################################################################################
resource "aws_apigatewayv2_api" "this" {
  name          = "${var.name}-api"
  protocol_type = "HTTP"
}
# Define a resource and method
resource "aws_apigatewayv2_route" "api_route" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /api/data" # Example route
  target             = "integrations/${aws_apigatewayv2_integration.mock_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.this.id
}
# Mock integration for testing
resource "aws_apigatewayv2_integration" "mock_integration" {
  api_id             = aws_apigatewayv2_api.this.id
  integration_type   = "MOCK"
  integration_method = "ANY" # Required for MOCK integration
}

resource "aws_apigatewayv2_stage" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = var.stage_name
  auto_deploy = true
}

################################################################################
# Cognito User Pool
################################################################################
resource "aws_cognito_user_pool" "this" {
  name = "${var.name}-user-pool"
}

resource "aws_cognito_user_pool_client" "this" {
  name                                 = "${var.name}-user-pool-client"
  user_pool_id                         = aws_cognito_user_pool.this.id
  generate_secret                      = true
  allowed_oauth_flows                  = ["implicit", "code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  allowed_oauth_flows_user_pool_client = true
  callback_urls                        = ["https://www.example.com"]
  logout_urls                          = ["https://www.example.com/logout"]
}

################################################################################
# Cognito Authorizer
################################################################################

resource "aws_apigatewayv2_authorizer" "this" {
  api_id           = aws_apigatewayv2_api.this.id
  name             = "${var.name}-cognito-authorizer"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  jwt_configuration {
    audience = [aws_cognito_user_pool_client.this.id]
    issuer   = "https://cognito-idp.${local.region}.amazonaws.com/${aws_cognito_user_pool.this.id}"
  }
}
