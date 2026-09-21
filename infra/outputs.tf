# ─────────────────────────────────────────────────────────────────────────
# Outputs — values Terraform prints after `apply` and exposes to
# `terraform output`, for use by scripts, curl, Postman, etc.
# ─────────────────────────────────────────────────────────────────────────
# Without these, the invoke URL, function name, and API ID would have to be
# looked up manually in the AWS console after every apply.

output "invoke_url" {
  description = "Full HTTPS URL for GET /hello"
  # aws_api_gateway_stage exposes `invoke_url` as the base
  # (".../<stage>"), so the "/hello" path segment is appended here to give
  # back a URL that's directly curl-able / paste-able into Postman.
  value = "${aws_api_gateway_stage.hello_stage.invoke_url}/hello"
}

output "lambda_function_name" {
  description = "Name of the deployed Lambda function"
  # Handy for boto3 scripts (see scripts/smoke_test.py, scripts/build_lambda.py)
  # that need the function name to call boto3.client("lambda").invoke(...)
  # or update_function_code(...) directly, bypassing API Gateway.
  value = aws_lambda_function.hello.function_name
}

output "rest_api_id" {
  description = "ID of the REST API"
  # Useful for looking the API up in the AWS Console or via
  # `aws apigateway get-rest-api --rest-api-id <this value>` without having
  # to hunt for it by name.
  value = aws_api_gateway_rest_api.hello_api.id
}

output "invoke_url_regional" {
  description = "Full HTTPS URL for GET /hello via the REGIONAL-endpoint API (see api_regional.tf) — compare against invoke_url, which is EDGE-optimized"
  value       = "${aws_api_gateway_stage.hello_stage_regional.invoke_url}/hello"
}

output "rest_api_id_regional" {
  description = "ID of the regional-endpoint REST API"
  value       = aws_api_gateway_rest_api.hello_api_regional.id
}

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
  value       = aws_cognito_user_pool.hr_users.id
}

output "cognito_client_id" {
  description = "Cognito public app client ID used by the UI's PKCE OAuth flow"
  value       = aws_cognito_user_pool_client.hr_ui_client.id
}

output "cognito_managed_login_domain" {
  description = "Cognito Managed Login hostname (hosted sign-in/sign-up pages)"
  value       = local.hr_cognito_domain
}

output "employee_table_name" {
  description = "Name of the DynamoDB employee table"
  value       = aws_dynamodb_table.employees.name
}
