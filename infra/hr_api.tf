# ─────────────────────────────────────────────────────────────────────────
# HR Lookup REST API: GET / (public, UI) and GET /employee/{id}
# (Cognito-authorized, backend)
# ─────────────────────────────────────────────────────────────────────────

resource "aws_api_gateway_rest_api" "hr_api" {
  name        = "hr-lookup-api"
  description = "Serverless HR lookup: GET / serves the UI, GET /employee/{id} is Cognito-protected"
}

# Computed from the REST API's own id (known as soon as the API is created)
# rather than from aws_api_gateway_stage — referencing the stage here would
# create a dependency cycle, since the UI Lambda (which needs this URL as
# its OAuth redirect_uri) is itself a dependency of the stage's deployment.
locals {
  hr_api_base_url   = "https://${aws_api_gateway_rest_api.hr_api.id}.execute-api.${var.aws_region}.amazonaws.com/${var.stage_name}/"
  hr_cognito_domain = "${var.cognito_domain_prefix}.auth.${var.aws_region}.amazoncognito.com"
}

# ── GET / → UI Lambda, no auth ─────────────────────────────────────────
resource "aws_api_gateway_method" "hr_root_get" {
  rest_api_id   = aws_api_gateway_rest_api.hr_api.id
  resource_id   = aws_api_gateway_rest_api.hr_api.root_resource_id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "hr_root_get" {
  rest_api_id             = aws_api_gateway_rest_api.hr_api.id
  resource_id             = aws_api_gateway_rest_api.hr_api.root_resource_id
  http_method             = aws_api_gateway_method.hr_root_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.hr_ui.invoke_arn
}

resource "aws_lambda_permission" "hr_ui_invoke" {
  statement_id  = "AllowAPIGatewayInvokeHRUi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hr_ui.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.hr_api.execution_arn}/*/GET/"
}

# ── /employee/{id} → Backend Lambda, Cognito authorizer ────────────────
resource "aws_api_gateway_resource" "employee" {
  rest_api_id = aws_api_gateway_rest_api.hr_api.id
  parent_id   = aws_api_gateway_rest_api.hr_api.root_resource_id
  path_part   = "employee"
}

resource "aws_api_gateway_resource" "employee_id" {
  rest_api_id = aws_api_gateway_rest_api.hr_api.id
  parent_id   = aws_api_gateway_resource.employee.id
  path_part   = "{id}"
}

# Validates the Cognito ID token sent as "Authorization: Bearer <token>"
# (the default identity_source) against this user pool before API Gateway
# ever invokes the backend Lambda.
resource "aws_api_gateway_authorizer" "cognito" {
  name          = "hr-cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.hr_api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.hr_users.arn]
}

resource "aws_api_gateway_method" "get_employee" {
  rest_api_id   = aws_api_gateway_rest_api.hr_api.id
  resource_id   = aws_api_gateway_resource.employee_id.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id

  request_parameters = {
    "method.request.path.id" = true
  }
}

resource "aws_api_gateway_integration" "get_employee" {
  rest_api_id             = aws_api_gateway_rest_api.hr_api.id
  resource_id             = aws_api_gateway_resource.employee_id.id
  http_method             = aws_api_gateway_method.get_employee.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.hr_backend.invoke_arn
}

resource "aws_lambda_permission" "hr_backend_invoke" {
  statement_id  = "AllowAPIGatewayInvokeHRBackend"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hr_backend.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.hr_api.execution_arn}/*/GET/employee/*"
}

# ── Deploy + publish ─────────────────────────────────────────────────────
resource "aws_api_gateway_deployment" "hr" {
  rest_api_id = aws_api_gateway_rest_api.hr_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_method.hr_root_get.id,
      aws_api_gateway_integration.hr_root_get.id,
      aws_api_gateway_resource.employee.id,
      aws_api_gateway_resource.employee_id.id,
      aws_api_gateway_method.get_employee.id,
      aws_api_gateway_integration.get_employee.id,
      aws_api_gateway_authorizer.cognito.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.hr_root_get,
    aws_api_gateway_integration.get_employee,
  ]
}

resource "aws_api_gateway_stage" "hr" {
  deployment_id = aws_api_gateway_deployment.hr.id
  rest_api_id   = aws_api_gateway_rest_api.hr_api.id
  stage_name    = var.stage_name
}
