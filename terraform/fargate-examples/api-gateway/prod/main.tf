terraform {
  required_version = ">= 1.3"

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
# ACM Certificates
################################################################################

# Prod Certificate in eu-west-2
resource "aws_acm_certificate" "prod_api_cert" {
  provider                  = aws.prod
  domain_name               = "api.cleanlinkportal.co.uk"
  validation_method         = "DNS"
  subject_alternative_names = ["cleanlinkportal.co.uk"]
  tags = {
    Name = "Prod API Certificate"
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "prod_api_cert_validation" {
  provider                = aws.prod
  certificate_arn         = aws_acm_certificate.prod_api_cert.arn
  validation_record_fqdns = [for dvo in aws_acm_certificate.prod_api_cert.domain_validation_options : dvo.resource_record_name]
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
  route_key          = "ANY /{proxy+}" # Greedy path variable to match any path
  target             = "integrations/${aws_apigatewayv2_integration.http_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.this.id
}

# Integration with the load balancer
resource "aws_apigatewayv2_integration" "http_integration" {
  api_id             = aws_apigatewayv2_api.this.id
  integration_type   = "HTTP_PROXY"
  integration_uri    = "${var.lb_service_url}/{proxy}"
  integration_method = "ANY"
}

resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/api_gateway/${var.name}-api-logs"
  retention_in_days = 30 # Adjust as needed
  tags = {
    Name        = "${var.name}-api-log-group"
    Environment = "prod"
  }
}

resource "aws_apigatewayv2_stage" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = var.stage_name
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
    format          = "$context.identity.sourceIp - - [$context.requestTime] \"$context.httpMethod $context.routeKey $context.protocol\" $context.status $context.responseLength $context.requestId"
  }
}

################################################################################
# Custom Domain Names
################################################################################
resource "aws_apigatewayv2_domain_name" "prod_api_domain" {
  provider    = aws.prod
  domain_name = "api.cleanlinkportal.co.uk"
  domain_name_configuration {
    certificate_arn = aws_acm_certificate_validation.prod_api_cert_validation.certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}

resource "aws_apigatewayv2_api_mapping" "prod_api_mapping" {
  provider    = aws.prod
  api_id      = aws_apigatewayv2_api.this.id
  domain_name = aws_apigatewayv2_domain_name.prod_api_domain.id
  stage       = aws_apigatewayv2_stage.this.id
}

################################################################################
# Cognito User Pool - Using the one from dev via SSM parameters
################################################################################

# Get Cognito data from SSM parameters (dev environment)
data "aws_ssm_parameter" "user_pool_id" {
  provider = aws.dev
  name     = "/${var.name}/user_pool_id"
}

data "aws_ssm_parameter" "user_pool_client_id" {
  provider = aws.dev
  name     = "/${var.name}/user_pool_client_id"
}

data "aws_ssm_parameter" "user_pool_client_auth_id" {
  provider = aws.dev
  name     = "/${var.name}/user_pool_client_auth_id"
}

data "aws_cognito_user_pool" "this" {
  provider     = aws.dev
  user_pool_id = data.aws_ssm_parameter.user_pool_id.value
}

data "aws_cognito_user_pool_client" "this" {
  provider     = aws.dev
  user_pool_id = data.aws_cognito_user_pool.this.id
  client_id    = data.aws_ssm_parameter.user_pool_client_id.value
}

data "aws_cognito_user_pool_client" "user_auth" {
  provider     = aws.dev
  user_pool_id = data.aws_cognito_user_pool.this.id
  client_id    = data.aws_ssm_parameter.user_pool_client_auth_id.value
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
    audience = [data.aws_cognito_user_pool_client.this.id, data.aws_cognito_user_pool_client.user_auth.id]
    issuer   = "https://cognito-idp.${local.region}.amazonaws.com/${data.aws_cognito_user_pool.this.id}"
  }
}

################################################################################
# API Gateway Execution Logging
################################################################################
resource "aws_api_gateway_account" "this" {
  cloudwatch_role_arn = aws_iam_role.cloudwatch_role.arn
}

resource "aws_iam_role" "cloudwatch_role" {
  name = "${var.name}-apigw-cw-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "cloudwatch_policy" {
  name = "${var.name}-apigw-cw-policy"
  role = aws_iam_role.cloudwatch_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents",
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

################################################################################
# Providers
################################################################################

provider "aws" {
  alias  = "prod"
  region = var.region
}

provider "aws" {
  alias  = "dev"
  region = var.region
}
