# ─────────────────────────────────────────────────────────────────────────
# Second REST API: same GET /hello route, same Lambda function as api.tf's
# hello_api, but a REGIONAL endpoint instead of the default EDGE-optimized
# type. Exists to compare latency characteristics between the two endpoint
# types against an identical backend.
# ─────────────────────────────────────────────────────────────────────────

resource "aws_api_gateway_rest_api" "hello_api_regional" {
  name        = "hello-api-regional"
  description = "Regional-endpoint REST API exposing GET /hello, sharing the hello Lambda with the edge-optimized API"

  # Omitting this block, as api.tf's hello_api does, defaults to
  # EDGE-optimized: AWS fronts the API with a CloudFront distribution for
  # global latency. REGIONAL serves directly from this deployment's own
  # region with no CloudFront in front - the deliberate contrast here.
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "hello_regional" {
  rest_api_id = aws_api_gateway_rest_api.hello_api_regional.id
  parent_id   = aws_api_gateway_rest_api.hello_api_regional.root_resource_id
  path_part   = "hello"
}

resource "aws_api_gateway_method" "get_hello_regional" {
  rest_api_id   = aws_api_gateway_rest_api.hello_api_regional.id
  resource_id   = aws_api_gateway_resource.hello_regional.id
  http_method   = "GET"
  authorization = "NONE"
}

# Points at the same aws_lambda_function.hello declared in lambda.tf - this
# is the "share and trigger the same Lambda function" requirement. Nothing
# about the function itself is duplicated; only the API Gateway front end
# is doubled.
resource "aws_api_gateway_integration" "lambda_integration_regional" {
  rest_api_id             = aws_api_gateway_rest_api.hello_api_regional.id
  resource_id             = aws_api_gateway_resource.hello_regional.id
  http_method             = aws_api_gateway_method.get_hello_regional.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.hello.invoke_arn
}

# A separate permission statement is required even though it's the same
# Lambda function: a resource-based Lambda policy statement's source_arn
# is scoped to one specific REST API's execution_arn, and this regional API
# has a different api_id - and therefore a different execution_arn - than
# hello_api in api.tf. One statement can't cover two different APIs.
resource "aws_lambda_permission" "apigw_invoke_regional" {
  statement_id  = "AllowAPIGatewayInvokeRegional"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.hello_api_regional.execution_arn}/*/${aws_api_gateway_method.get_hello_regional.http_method}/hello"
}

resource "aws_api_gateway_deployment" "hello_deployment_regional" {
  rest_api_id = aws_api_gateway_rest_api.hello_api_regional.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.hello_regional.id,
      aws_api_gateway_method.get_hello_regional.id,
      aws_api_gateway_integration.lambda_integration_regional.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_api_gateway_integration.lambda_integration_regional]
}

# Deployed into the same region as hello_api: there is only one `provider
# "aws"` block in this project (providers.tf), so both REST APIs are
# created through that same single regional endpoint regardless - no
# separate provider or region configuration is needed for this.
resource "aws_api_gateway_stage" "hello_stage_regional" {
  deployment_id = aws_api_gateway_deployment.hello_deployment_regional.id
  rest_api_id   = aws_api_gateway_rest_api.hello_api_regional.id
  stage_name    = var.stage_name
}
