# Employee Database with API Gateway and Cognito

---

## Serverless HR Lookup Application

Develop an end-to-end serverless HR application on AWS. The application must allow an authenticated user to look up employee information using an Employee ID.

---

## Repository layout

```
Serverless-HR-Lookup-Application/
├── README.md                (this file)
├── LICENSE
├── .gitignore                root-level, Terraform + Python + OS patterns
├── infra/                    Terraform root — IAM role, Lambda function, REST APIs,
│   │                         Cognito authentication server, DynamoDb table, deployment/stage each
│   ├── providers.tf          AWS provider + region
│   ├── variables.tf          aws_region, stage_name
│   ├── hr_lambda.tf          IAM role, Lambda function resource
│   ├── hr_api.tf             REST API, /employee resource, GET method,
│   │                         integration, Lambda permission, deployment, stage
│   ├── cognito.tf            Cognito authentication server
│   ├── dynamodb.tf           DynamoDB table and items
│   ├── outputs.tf            hr_app_url, hr_employee_lookup_url, cognito_user_pool_id,
│   │                         cognito_client_id, cognito_managed_login_domain, employee_table_name
│   ├── terraform.tfvars.example
│   └── .terraform.lock.hcl   committed, pins provider versions
└── lambda/                   Lambda function source (backend/handler.py and ui/handler.py)
    ├── backend/
    │   └── handler.py        Lambda function source
    └── ui/
        └── handler.py        Lambda function source
```

`terraform apply` packages `lambda/backend/handler.py` and `lambda/ui/handler.py` into zip files automatically
(via the `archive_file` data source in `infra/hr_lambda.tf`) — you do not need to
run anything by hand before the first deploy.

---

## 0. Prerequisites

- An **AWS account.**
- **AWS region.** Any region works; pick one and use it
  consistently across the Terraform provider block (e.g. `us-east-1`).
- An IAM user (not root) with programmatic access keys.
  The user needs permission to create/manage: Lambda functions, IAM roles,
  API Gateway REST APIs, and CloudWatch Logs. For a personal account,
  attaching `AdministratorAccess` to this IAM user is the simplest option;
  for a shared account, use an IAM policy scoped to just those permissions
  instead.
- Terraform >= 1.5 ([install guide](https://developer.hashicorp.com/terraform/install))
- Python 3.9+ and `pip`
- AWS CLI (optional but convenient): `pip install awscli`
- **Free Tier note.** Lambda (1M requests/month) is Always Free. API Gateway
  REST API (1M calls/month) is free only within an account's 12-month
  new-customer window — verify current terms rather than assuming this.
  At the volume this project generates (a handful of manual test calls),
  cost is effectively zero either way.

Configure your credentials once, in the region you intend to use throughout:

```bash
aws configure
# AWS Access Key ID / Secret Access Key / region (e.g. us-east-1) / output format
```

Verify the CLI can see your account before touching Terraform:

```bash
aws sts get-caller-identity
```

---

## 1. Application Requirements

The user enters an **Employee ID** and selects **Search**.

The application retrieves the employee record from DynamoDB and displays all of the following fields:

- Employee ID
- Name
- Salary
- Date of Join
- Description

---

## 2. Application Architecture

The application implements the following logical architecture:

```
                        User Browser
                              |
                              | HTTPS
                              v
                       API Gateway REST API
                        /               \
                       /                 \
                  GET /              GET /employee/{id}
                    |                       |
                    v                       v
               UI Lambda             Cognito Authorizer
                    |                       |
             HTML/CSS/JavaScript            |
                                            v
                                      Backend Lambda
                                            |
                                       IAM Role
                                            |
                                            v
                                        DynamoDB


                    Amazon Cognito User Pool
                              |
                        Managed Login
                              |
                     OAuth 2.0 + PKCE
```

Uses the following AWS services:

- Amazon API Gateway REST API
- AWS Lambda
- Amazon DynamoDB
- Amazon Cognito
- AWS IAM

The browser does not directly access DynamoDB.

---

## 3. APIs to Implement

### GET /

Returns the application's HTML/CSS/JavaScript interface.

### GET /employee/{id}

Retrieves the complete employee record.

Sends the Cognito **ID token**, not the access token, in the *Authorization* header.

The API does:

- Require authentication.
- Accept an Employee ID as the lookup key.
- Retrieve the employee using Employee ID.
- Return all employee fields.
- Return an appropriate error for an invalid or unknown Employee ID.

Any authenticated user may look up any Employee ID.

---

## 4. DynamoDB

Creates an employee table using:

Partition Key: EmployeeID

Each employee record contains:

- EmployeeID
- Name
- Salary
- DateOfJoin
- Description

*Description* is stored as a string.

Populated the table with sufficient sample records to demonstrate the application.

At least **one employee record represents a student**. That record contains:

- Their name in the *Name* field
- Their AWS user ARN in the *Description* field

The backend performs a key-based lookup using the Employee ID.

---

## 5. Authentication

Configures an **Amazon Cognito User Pool** with:

- Cognito Managed Login
- Public application client
- No client secret
- OAuth 2.0 Authorization Code Grant
- PKCE

The authentication flow is:
```
Browser
   |
   v
Cognito Managed Login
   |
   v
User Authentication
   |
   v
Authorization Code
   |
   v
Token Exchange using PKCE
   |
   v
Cognito Token
   |
   | Authorization: Bearer <token>
   v
API Gateway
   |
   v
Cognito Authorizer
   |
   v
Backend Lambda
```

Configured API Gateway so that:
GET /employee/{id}

is protected by the Cognito authorizer.

---

## 6. IAM

Creates an IAM execution role for the backend Lambda.

The role follows the principle of least privilege and allows only the DynamoDB operations required for the employee lookup.

Does not expose AWS credentials in application code.

---

## Build & Deploy the infrastructure Steps

```bash
cd Serverless-HR-Lookup-Application/infra
cp terraform.tfvars.example terraform.tfvars   # set aws_region
# edit terraform.tfvars if you want a region other than us-east-1

terraform init
terraform plan     # review what will be created
terraform apply    # type "yes" to confirm
```

When it finishes, note the outputs:

```bash
terraform output hr_app_url

cd ..   # back to the project root
```

---

## 7. Testing Requirements

Test and demonstrate the following scenarios.

### Test 1 – Application Access

Open the application URL.

#### Expected result:

The application UI is successfully displayed in the browser.

### Test 2 – User Authentication

Authenticate using Cognito Managed Login.

#### Expected result:

A valid user can successfully log in and access the application.

### Test 3 – Valid Employee Lookup

Enter a valid Employee ID.

#### Expected result:

The application displays:
Employee ID
Name
Salary
Date of Join
Description

### Test 4 – Student Employee Record

Search for the Employee ID corresponding to your own student record.

#### Expected result:

The application displays your name and your AWS user ARN in the Description field.

### Test 5 – Invalid Employee ID

Enter an Employee ID that does not exist.

#### Expected result:

The application displays an appropriate error or Employee not found message.

### Test 6 – Unauthorized API Access

Invoke:
GET /employee/{id}

without a valid Cognito token.

#### Expected result:

API Gateway rejects the request and employee information is not returned.

---

## 8. Success Criteria

The homework is considered functionally complete when all of the following are demonstrated:

- The application UI is accessible over HTTPS.
- Cognito authentication works successfully.
- An unauthenticated request cannot access employee information.
- A valid Employee ID retrieves the correct DynamoDB record.
- The complete employee record is displayed.
- The DynamoDB table contains the required five fields.
- One employee record represents the student.
- The student's record contains the student's AWS user ARN in the Description field.
- Invalid Employee IDs are handled correctly.
- API Gateway successfully invokes Lambda.
- Lambda successfully retrieves data from DynamoDB.
- IAM permissions allow the required access without unnecessary privileges.

---

## 9. Source Code and GitHub

All source code for the homework must be committed to a GitHub repository.
You can use any automation - terraform, boto3, etc. You can use AI Generated code and use AI assistance to debug the setup. Ensure you document the AI tools used for various steps.
The repository should contain:

- UI source code
- Lambda source code
- Supporting configuration or scripts you created
- A README with basic deployment and testing instructions

Submit the GitHub repository link through Canvas.
Do not submit the source code as a ZIP file.
Ensure the instructor has permission to access the repository.
Do not commit:

- AWS access keys
- AWS secret access keys
- Client secrets
- Passwords
- Authentication tokens

---

## 10. Screenshots and Documentation

Submit your Functional Specification document and supporting evidence through Canvas.
Include:

- Architecture diagram
- Authentication-flow diagram
- Cognito login-page screenshot
- Successful application UI screenshot
- Successful employee lookup screenshot
- Screenshot showing the student employee record
- Relevant AWS service configuration screenshots
- Exported API Gateway REST API definition

```
GET /
GET /employee/{id}
```
For application and login screenshots, submit full browser screenshots that include the browser URL bar. The URL must be visible so that the deployed application endpoint can be verified.
Also document:

- Cognito Client ID
- Cognito User Pool Subject UUID (sub)
- Cognito Managed Login domain
- API Gateway URL
- GitHub repository URL

Do not submit a client secret.

---

## Terraform Resources

| Resource | Purpose |
|---|---|
| `aws_dynamodb_table` | Stores employee records using EmployeeID as the partition key |
| `aws_dynamodb_table_item` | Creates the required sample employee records |
| `aws_iam_role` | Execution role assumed by the backend Lambda |
| `aws_iam_role_policy` | Grants the Lambda only the DynamoDB operations it needs |
| `aws_lambda_function` | Backend Lambda that retrieves employees from DynamoDB |
| `aws_lambda_function` | UI Lambda that serves the application frontend |
| `aws_api_gateway_rest_api` | API Gateway REST API |
| `aws_api_gateway_resource` | Creates /employee/{id} |
| `aws_api_gateway_method` | Creates the GET method |
| `aws_api_gateway_authorizer` | Connects API Gateway to Cognito |
| `aws_api_gateway_integration` | Connects API Gateway to the backend Lambda |
| `aws_lambda_permission` | Allows API Gateway to invoke the Lambda |
| `aws_api_gateway_deployment` | Deploys the REST API configuration |
| `aws_api_gateway_stage` | Publishes the deployment under the configured stage |
| `Cognito` resources | User Pool, app client, domain, etc. |

`outputs.tf` exposes `variables and url to be used later.

The `archive_file` data source in `hr_lambda.tf` produces zip files from
`lambda/*/handler.py` automatically on `terraform plan`/`apply` —
`aws_lambda_function` references it via `filename` + `source_code_hash`, so
editing the handler and re-running `terraform apply` is enough to redeploy.

---

## 11. AWS Resource Cleanup Tear down

After you have completed testing and captured the required screenshots, do not leave the application infrastructure running unnecessarily.
Delete or disable AWS resources that are no longer required for the homework. Depending on your implementation, this may include:

- API Gateway APIs or stages
- Lambda functions
- DynamoDB tables
- Cognito resources
- IAM roles created specifically for the exercise
- Any additional AWS resources you created

Remove every resource this project created so nothing keeps running in your
account:

```bash
cd infra
terraform destroy   # type "yes" to confirm
cd ..
```

Some AWS resources can incur charges even when they are not actively being used.
It is your responsibility to verify that unnecessary resources have been removed after completing the assignment.

---

## Cost

Lambda (1M requests/month) is part of AWS's Always Free tier.
API Gateway REST API (1M calls/month **per API**) is free only
within an account's 12-month new-customer window. At
the handful of manual calls this project generates, expect
effectively $0 either way — but run `terraform destroy` when you're done so
nothing is left running.
