output "api_endpoint" {
  description = "API Gateway endpoint URL"
  value       = aws_apigatewayv2_stage.this.invoke_url
}

output "user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.this.id
}

output "user_pool_client_id" {
  description = "Cognito User Pool Client ID (server-to-server)"
  value       = aws_cognito_user_pool_client.this.id
}

output "user_auth_client_id" {
  description = "Cognito User Pool Client ID (user authentication)"
  value       = aws_cognito_user_pool_client.user_auth.id
}

# Add SSM parameters for sharing across environments
resource "aws_ssm_parameter" "user_pool_id" {
  name        = "/${var.name}/user_pool_id"
  description = "Cognito User Pool ID for ${var.name}"
  type        = "String"
  value       = aws_cognito_user_pool.this.id
  overwrite   = true
}

resource "aws_ssm_parameter" "user_pool_client_id" {
  name        = "/${var.name}/user_pool_client_id"
  description = "Cognito User Pool Client ID (server-to-server) for ${var.name}"
  type        = "String"
  value       = aws_cognito_user_pool_client.this.id
  overwrite   = true
}

resource "aws_ssm_parameter" "user_pool_client_auth_id" {
  name        = "/${var.name}/user_pool_client_auth_id"
  description = "Cognito User Pool Client ID (user authentication) for ${var.name}"
  type        = "String"
  value       = aws_cognito_user_pool_client.user_auth.id
  overwrite   = true
}
