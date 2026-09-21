# ─────────────────────────────────────────────────────────────────────────
# DynamoDB: Employees table + sample data
# ─────────────────────────────────────────────────────────────────────────
# Partition-key-only table — every lookup in this app is "give me the one
# record whose EmployeeID equals X", so no sort key is needed.

resource "aws_dynamodb_table" "employees" {
  name         = var.employee_table_name
  billing_mode = "PAY_PER_REQUEST" # no capacity planning needed for a demo-sized table
  hash_key     = "EmployeeID"

  attribute {
    name = "EmployeeID"
    type = "S"
  }
}

# Used to stamp the current caller's ARN into the "you, the student" record
# below, instead of requiring it to be typed in by hand.
data "aws_caller_identity" "current" {}

resource "aws_dynamodb_table_item" "sample_1001" {
  table_name = aws_dynamodb_table.employees.name
  hash_key   = aws_dynamodb_table.employees.hash_key

  item = jsonencode({
    EmployeeID  = { S = "1001" }
    Name        = { S = "Alice Chen" }
    Salary      = { N = "92000" }
    DateOfJoin  = { S = "2024-01-15" }
    Description = { S = "Cloud Engineering employee" }
  })
}

resource "aws_dynamodb_table_item" "sample_1002" {
  table_name = aws_dynamodb_table.employees.name
  hash_key   = aws_dynamodb_table.employees.hash_key

  item = jsonencode({
    EmployeeID  = { S = "1002" }
    Name        = { S = "Marcus Reed" }
    Salary      = { N = "78000" }
    DateOfJoin  = { S = "2022-06-01" }
    Description = { S = "Platform Support employee" }
  })
}

resource "aws_dynamodb_table_item" "sample_1003" {
  table_name = aws_dynamodb_table.employees.name
  hash_key   = aws_dynamodb_table.employees.hash_key

  item = jsonencode({
    EmployeeID  = { S = "1003" }
    Name        = { S = "Priya Nair" }
    Salary      = { N = "105000" }
    DateOfJoin  = { S = "2021-03-22" }
    Description = { S = "Senior Backend Engineer" }
  })
}

resource "aws_dynamodb_table_item" "sample_1004" {
  table_name = aws_dynamodb_table.employees.name
  hash_key   = aws_dynamodb_table.employees.hash_key

  item = jsonencode({
    EmployeeID  = { S = "1004" }
    Name        = { S = "Diego Alvarez" }
    Salary      = { N = "61000" }
    DateOfJoin  = { S = "2025-09-02" }
    Description = { S = "HR Operations Coordinator" }
  })
}

# The assignment-required record representing the student themselves —
# Name is set via a variable, Description is the *actual* current AWS
# caller's ARN (not typed by hand), so it stays correct if the account/user
# it was applied under ever changes.
resource "aws_dynamodb_table_item" "sample_student" {
  table_name = aws_dynamodb_table.employees.name
  hash_key   = aws_dynamodb_table.employees.hash_key

  item = jsonencode({
    EmployeeID  = { S = var.student_employee_id }
    Name        = { S = var.student_name }
    Salary      = { N = "95000" }
    DateOfJoin  = { S = "2026-01-15" }
    Description = { S = data.aws_caller_identity.current.arn }
  })
}
