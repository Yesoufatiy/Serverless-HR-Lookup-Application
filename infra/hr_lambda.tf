# ─────────────────────────────────────────────────────────────────────────
# HR Lookup Lambda functions + their IAM execution roles
# ─────────────────────────────────────────────────────────────────────────

data "archive_file" "employee_ui_lambda" {
  type        = "zip"
  source_file = "${path.module}/../lambda/ui/handler.py"
  output_path = "${path.module}/employee_ui.zip"
}

data "archive_file" "employee-lookup_lambda" {
  type        = "zip"
  source_file = "${path.module}/../lambda/backend/handler.py"
  output_path = "${path.module}/employee-lookup.zip"
}

# ── UI Lambda: serves the HTML/CSS/JS page, no AWS data access at all ───
resource "aws_iam_role" "employee_ui_exec" {
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

resource "aws_iam_role_policy_attachment" "employee_ui_basic_execution" {
  role       = aws_iam_role.employee_ui_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "employee_ui" {
  function_name = "hr-ui-function"
  role          = aws_iam_role.employee_ui_exec.arn
  handler       = "handler.handler"
  runtime       = "python3.12"

  filename         = data.archive_file.employee_ui_lambda.output_path
  source_code_hash = data.archive_file.employee_ui_lambda.output_base64sha256

  timeout = 5

  environment {
    variables = {
      COGNITO_DOMAIN    = local.hr_cognito_domain
      COGNITO_CLIENT_ID = aws_cognito_user_pool_client.employee_ui_client.id
      REDIRECT_URI      = local.employee-directory-api_base_url
    }
  }
}

# ── Backend Lambda: reads DynamoDB, never touched directly by the browser ─
resource "aws_iam_role" "employee-lookup_exec" {
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

resource "aws_iam_role_policy_attachment" "employee-lookup_basic_execution" {
  role       = aws_iam_role.employee-lookup_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Least privilege: the only DynamoDB action this role ever needs is a
# key-based GetItem on this one table — no Scan/Query/Put/Delete, and no
# access to any other table.
resource "aws_iam_role_policy" "employee-lookup_dynamodb_get" {
  name = "hr-backend-dynamodb-getitem"
  role = aws_iam_role.employee-lookup_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem"]
      Resource = aws_dynamodb_table.employees.arn
    }]
  })
}

resource "aws_lambda_function" "employee-lookup" {
  function_name = "hr-backend-function"
  role          = aws_iam_role.employee-lookup_exec.arn
  handler       = "handler.handler"
  runtime       = "python3.12"

  filename         = data.archive_file.employee-lookup_lambda.output_path
  source_code_hash = data.archive_file.employee-lookup_lambda.output_base64sha256

  timeout = 5

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.employees.name
    }
  }
}
