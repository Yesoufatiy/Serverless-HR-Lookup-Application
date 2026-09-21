# ─────────────────────────────────────────────────────────────────────────
# HR Lookup Lambda functions + their IAM execution roles
# ─────────────────────────────────────────────────────────────────────────

data "archive_file" "hr_ui_lambda" {
  type        = "zip"
  source_file = "${path.module}/../lambda/ui/handler.py"
  output_path = "${path.module}/hr_ui.zip"
}

data "archive_file" "hr_backend_lambda" {
  type        = "zip"
  source_file = "${path.module}/../lambda/backend/handler.py"
  output_path = "${path.module}/hr_backend.zip"
}

# ── UI Lambda: serves the HTML/CSS/JS page, no AWS data access at all ───
resource "aws_iam_role" "hr_ui_exec" {
  name = "hr-ui-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "hr_ui_basic_execution" {
  role       = aws_iam_role.hr_ui_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "hr_ui" {
  function_name = "hr-ui-function"
  role          = aws_iam_role.hr_ui_exec.arn
  handler       = "handler.handler"
  runtime       = "python3.12"

  filename         = data.archive_file.hr_ui_lambda.output_path
  source_code_hash = data.archive_file.hr_ui_lambda.output_base64sha256

  timeout = 5

  environment {
    variables = {
      COGNITO_DOMAIN    = local.hr_cognito_domain
      COGNITO_CLIENT_ID = aws_cognito_user_pool_client.hr_ui_client.id
      REDIRECT_URI      = local.hr_api_base_url
    }
  }
}

# ── Backend Lambda: reads DynamoDB, never touched directly by the browser ─
resource "aws_iam_role" "hr_backend_exec" {
  name = "hr-backend-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "hr_backend_basic_execution" {
  role       = aws_iam_role.hr_backend_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Least privilege: the only DynamoDB action this role ever needs is a
# key-based GetItem on this one table — no Scan/Query/Put/Delete, and no
# access to any other table.
resource "aws_iam_role_policy" "hr_backend_dynamodb_get" {
  name = "hr-backend-dynamodb-getitem"
  role = aws_iam_role.hr_backend_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem"]
      Resource = aws_dynamodb_table.employees.arn
    }]
  })
}

resource "aws_lambda_function" "hr_backend" {
  function_name = "hr-backend-function"
  role          = aws_iam_role.hr_backend_exec.arn
  handler       = "handler.handler"
  runtime       = "python3.12"

  filename         = data.archive_file.hr_backend_lambda.output_path
  source_code_hash = data.archive_file.hr_backend_lambda.output_base64sha256

  timeout = 5

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.employees.name
    }
  }
}
