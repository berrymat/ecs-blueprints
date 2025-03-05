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

# Dev Certificate in eu-west-2
resource "aws_acm_certificate" "dev_api_cert" {
  provider                  = aws.dev
  domain_name               = "dev-api.cleanlinkportal.co.uk"
  validation_method         = "DNS"
  subject_alternative_names = ["dev.cleanlinkportal.co.uk"]
  tags = {
    Name = "Dev API Certificate"
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "dev_api_cert_validation" {
  provider                = aws.dev
  certificate_arn         = aws_acm_certificate.dev_api_cert.arn
  validation_record_fqdns = [for dvo in aws_acm_certificate.dev_api_cert.domain_validation_options : dvo.resource_record_name]
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
# Mock integration for testing
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
    Environment = "dev"
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
resource "aws_apigatewayv2_domain_name" "dev_api_domain" {
  provider    = aws.dev
  domain_name = "dev-api.cleanlinkportal.co.uk"
  domain_name_configuration {
    certificate_arn = aws_acm_certificate_validation.dev_api_cert_validation.certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}
resource "aws_apigatewayv2_api_mapping" "dev_api_mapping" {
  provider    = aws.dev
  api_id      = aws_apigatewayv2_api.this.id
  domain_name = aws_apigatewayv2_domain_name.dev_api_domain.id
  stage       = aws_apigatewayv2_stage.this.id
}

################################################################################
# Cognito User Pool
################################################################################
#note: this does not use the provider, as it can only be created once.

resource "aws_cognito_user_pool_domain" "this" {
  domain       = "cleanlink-auth-${var.name}"
  user_pool_id = aws_cognito_user_pool.this.id
}

resource "aws_cognito_user_pool" "this" {
  name = "${var.name}-user-pool"
  
  # Add UI customization
  admin_create_user_config {
    allow_admin_create_user_only = false
  }
  
  auto_verified_attributes = ["email"]
  
  # Configure password policy
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }
  
  # Enable some features
  mfa_configuration = "OFF"
  
  # UI customization
  user_pool_add_ons {
    advanced_security_mode = "OFF"
  }
}

resource "aws_cognito_user_pool_client" "this" {
  name                                 = "${var.name}-user-pool-client"
  user_pool_id                         = aws_cognito_user_pool.this.id
  generate_secret                      = true
  explicit_auth_flows                  = ["USER_PASSWORD_AUTH"]
  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_scopes                 = ["api/health"]
  allowed_oauth_flows_user_pool_client = true
  prevent_user_existence_errors        = "ENABLED"
}

# Second client for user-based authentication (mobile)
resource "aws_cognito_user_pool_client" "user_auth" {
  name                                 = "${var.name}-user-auth-client"
  user_pool_id                         = aws_cognito_user_pool.this.id
  generate_secret                      = true
  explicit_auth_flows                  = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH", 
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["openid", "email", "profile", "api/health"]
  allowed_oauth_flows_user_pool_client = true
  prevent_user_existence_errors        = "ENABLED"
  
  # UI customization for Auth screen
  supported_identity_providers         = ["COGNITO"]
  
  # Support mobile apps and web apps
  callback_urls                        = [
    "https://dev-api.cleanlinkportal.co.uk/callback",
    "com.cleanlinkportal.app://callback",
    "https://oauth.pstmn.io/v1/browser-callback"
  ]
  default_redirect_uri                 = "https://oauth.pstmn.io/v1/browser-callback"
  
  # Add logout URLs
  logout_urls                          = ["https://dev-api.cleanlinkportal.co.uk/logout"]
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
    audience = [aws_cognito_user_pool_client.this.id, aws_cognito_user_pool_client.user_auth.id]
    issuer   = "https://cognito-idp.${local.region}.amazonaws.com/${aws_cognito_user_pool.this.id}"
  }
}

################################################################################
# Providers
################################################################################
provider "aws" {
  alias  = "dev"
  region = var.region
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

resource "aws_cognito_resource_server" "this" {
  identifier   = "api"
  name         = "api"
  user_pool_id = aws_cognito_user_pool.this.id

  scope {
    scope_name        = "health"
    scope_description = "access to health"
  }
}
