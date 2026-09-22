# ─────────────────────────────────────────────────────────────────────────
# Outputs — values Terraform prints after `apply` and exposes to
# `terraform output`, for use by scripts, curl, Postman, etc.
# ─────────────────────────────────────────────────────────────────────────

# ── HR Lookup application ──────────────────────────────────────────────

output "hr_app_url" {
  description = "URL for the HR Lookup app's UI (GET /) — open this in a browser"
  value       = aws_api_gateway_stage.hr.invoke_url
}

output "hr_employee_lookup_url" {
  description = "Base URL for GET /employee/{id} (requires Authorization: Bearer <Cognito ID token>)"
  value       = "${aws_api_gateway_stage.hr.invoke_url}/employee"
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID, for creating test users via the AWS Console/CLI"
  value       = aws_cognito_user_pool.employee-directory-users.id
}

output "cognito_client_id" {
  description = "Cognito public app client ID used by the UI's PKCE OAuth flow"
  value       = aws_cognito_user_pool_client.employee_ui_client.id
}

output "cognito_managed_login_domain" {
  description = "Cognito Managed Login hostname (hosted sign-in/sign-up pages)"
  value       = local.hr_cognito_domain
}

output "employee_table_name" {
  description = "Name of the DynamoDB employee table"
  value       = aws_dynamodb_table.employees.name
}
