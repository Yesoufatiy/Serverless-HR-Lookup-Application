# Simple API Gateway → Lambda "Hello" — Terraform + boto3 Plan

---

## 1. Project Summary

`GET /hello` is exposed by two independent REST APIs — one EDGE-optimized
(the default endpoint type), one REGIONAL — both fronting the exact same
Lambda function, which returns a JSON message and echoes back any query
string parameters on the request. Two gateways in front of one function so
their latency characteristics can be compared directly against an identical
backend.

```
        HTTPS                               HTTPS
Postman / Browser                    Postman / Browser
        │                                     │
        ▼                                     ▼
   API Gateway                            API Gateway
 (EDGE-optimized)                         (REGIONAL)
        │                                     │
   GET /hello                            GET /hello
        │                                     │
        └───────────────┬─────────────────────┘
                         ▼
                    AWS Lambda
                         │
                         ▼
               {"message":"Hello"}
```

Both gateways route `GET /hello` to the same `aws_lambda_function.hello` —
the function itself is not duplicated, only the API Gateway front end is.

### Response contract

```json
{
  "message": "Hello",
  "params": {}
}
```

`params` holds whatever query string parameters were on the request (empty
object if none), e.g. `GET /hello?name=CS218` returns
`{"message": "Hello", "params": {"name": "CS218"}}`. Returned with
`Content-Type: application/json` and HTTP 200. Path params and request body
are not read.

---

## 2. Prerequisites

1. **AWS account + region.** Any region works; pick one and use it
   consistently across the Terraform provider block and every boto3 client
   (e.g. `us-east-1`).
2. **IAM user, not root**, with programmatic access (`aws configure`) and
   permissions for: `lambda:*`, `apigateway:*`, `iam:CreateRole` /
   `iam:PutRolePolicy` / `iam:PassRole`, `logs:*` (for CloudWatch Logs).
3. **Tooling:**
   ```bash
   pip install boto3
   terraform -version   # >= 1.5
   aws configure
   ```
4. **Free Tier note.** Lambda (1M requests/month) is Always Free. API Gateway
   REST API (1M calls/month) is free only within an account's 12-month
   new-customer window — verify current terms rather than assuming this.
   At the volume this project generates (a handful of manual test calls),
   cost is effectively zero either way.

---

## 3. Repository Layout

```
api-gateway/
├── Plan.md                  (this file)
├── README.md
├── LICENSE
├── .gitignore                root-level, Terraform + Python + OS patterns
├── infra/
│   ├── providers.tf          AWS provider + region
│   ├── variables.tf          aws_region, stage_name
│   ├── lambda.tf             IAM role, Lambda function resource
│   ├── api.tf                EDGE-optimized REST API, /hello resource, GET method,
│   │                         integration, Lambda permission, deployment, stage
│   ├── api_regional.tf       Same, but REGIONAL endpoint type — shares the same
│   │                         Lambda function as api.tf, its own permission/deployment/stage
│   ├── outputs.tf            invoke_url, invoke_url_regional, lambda_function_name,
│   │                         rest_api_id, rest_api_id_regional
│   ├── terraform.tfvars.example
│   └── .terraform.lock.hcl   committed, pins provider versions
├── lambda/
│   └── hello/
│       └── handler.py        Lambda function source
└── scripts/
    ├── requirements.txt
    ├── build_lambda.py       zip handler.py; optionally push via boto3 update_function_code
    ├── smoke_test.py         call the deployed endpoint via direct invoke + HTTPS, assert response
    └── verify_teardown.py    confirm Lambda/API/IAM role are gone after terraform destroy
```

Terraform owns all AWS resource state. boto3 covers what Terraform doesn't:
zipping Lambda source into a deployment package, and calling the live
endpoint over HTTP the way a client would.

---

## 4. Lambda Function

`lambda/hello/handler.py`:

```python
import json


def handler(event, context):
    params = event.get("queryStringParameters") or {}
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"message": "Hello", "params": params}),
    }
```

Runtime: `python3.12`. No third-party dependencies, so the deployment package
is just the zipped source file — no `pip install -t` vendoring step needed.
`event["queryStringParameters"]` is populated directly by the API Gateway
`AWS_PROXY` integration; no Terraform configuration is required to pass query
parameters through.

---

## 5. Terraform Resources

| Resource | Purpose |
|---|---|
| `aws_iam_role` (lambda exec role) | Trust policy allowing `lambda.amazonaws.com` to assume it |
| `aws_iam_role_policy_attachment` | Attach `AWSLambdaBasicExecutionRole` (CloudWatch Logs write access) |
| `aws_lambda_function` | Deploys `hello.zip`, handler `handler.handler`, runtime `python3.12` — shared by both gateways below |
| `aws_api_gateway_rest_api` (`hello_api`) | EDGE-optimized REST API container (`hello-api`) — no `endpoint_configuration` block means AWS defaults to `EDGE` |
| `aws_api_gateway_resource` (`hello`) | Adds the `/hello` path under `hello_api`'s root |
| `aws_api_gateway_method` (`get_hello`) | `GET` on `hello_api`'s `/hello`, `authorization = "NONE"` |
| `aws_api_gateway_integration` (`lambda_integration`) | `AWS_PROXY` integration from `hello_api`'s method to `aws_lambda_function.hello` |
| `aws_lambda_permission` (`apigw_invoke`) | Grants `hello_api`'s execution ARN permission to invoke the Lambda |
| `aws_api_gateway_deployment` / `aws_api_gateway_stage` (`hello_deployment` / `hello_stage`) | Deploys and publishes `hello_api` under `var.stage_name` |
| `aws_api_gateway_rest_api` (`hello_api_regional`, `api_regional.tf`) | Second REST API container (`hello-api-regional`) — `endpoint_configuration { types = ["REGIONAL"] }` explicitly, the deliberate contrast with `hello_api` |
| `aws_api_gateway_resource` / `method` / `integration` (`*_regional`) | Same `/hello` `GET` route, on `hello_api_regional`, integrated to the **same** `aws_lambda_function.hello` — nothing about the function is duplicated |
| `aws_lambda_permission` (`apigw_invoke_regional`) | A distinct statement, since a Lambda resource policy's `source_arn` scopes to one REST API's execution ARN — `hello_api_regional` has a different `api_id` than `hello_api`, so one statement can't cover both |
| `aws_api_gateway_deployment` / `aws_api_gateway_stage` (`*_regional`) | Deploys and publishes `hello_api_regional`, under the same `var.stage_name` — both gateways live in the one AWS region this project's single `provider "aws"` block targets |

`outputs.tf` exposes `invoke_url` (EDGE, `hello_api`) and `invoke_url_regional`
(REGIONAL, `hello_api_regional`), both in the form
`https://<api-id>.execute-api.<region>.amazonaws.com/<stage>/hello` — the two
`api-id` values differ since they're separate REST APIs, everything else
about the URL shape is identical. Both feed directly into `smoke_test.py` and
into Postman.

The `archive_file` data source in `lambda.tf` produces `hello.zip` from
`lambda/hello/handler.py` automatically on `terraform plan`/`apply` —
`aws_lambda_function` references it via `filename` + `source_code_hash`, so
editing the handler and re-running `terraform apply` is enough to redeploy.

---

## 6. boto3 Scripts

### `scripts/build_lambda.py`
Zips `lambda/hello/handler.py` into `infra/hello.zip` with Python's `zipfile`
module. Not required for a normal `terraform apply`, since Terraform packages
the function itself; useful for inspecting the exact deployment package, or
for pushing a handler change straight to the live function with `--deploy`
(boto3 `update_function_code`) without a full `terraform apply`.

### `scripts/smoke_test.py`
Checks the deployed API five ways, against both gateways:
1. **Direct Lambda invoke**, no query params — `boto3.client("lambda").invoke(...)`,
   asserts `{"message": "Hello", "params": {}}`. Confirms the function itself
   works, independent of either API Gateway.
2. **HTTP call through the EDGE-optimized stage** (`--invoke-url`), `?name=CS218` —
   `urllib.request`, asserts `{"message": "Hello", "params": {"name": "CS218"}}`.
3. **HTTP call through the REGIONAL stage** (`--invoke-url-regional`), same
   assertion. (2) and (3) failing independently of each other narrows a bug
   to that specific gateway's wiring, not the shared function.
4. **Connection-phase timing, EDGE endpoint** — shells out to `curl -w` for
   DNS lookup, TCP connect, TLS handshake, time to first byte, total time,
   and HTTP status code. These are libcurl-level timers; `urllib` has no
   equivalent without hooking sockets directly, so this is a subprocess call
   rather than a pure Python check.
5. **Connection-phase timing, REGIONAL endpoint** — same breakdown, so (4)
   and (5) can be compared directly. That comparison — does REGIONAL's lack
   of a CloudFront hop actually change TCP/TLS/TTFB versus EDGE from this
   particular network vantage point — is the reason this project runs two
   gateways in front of one Lambda function at all.

If (1) fails, the bug is in the Lambda handler. If (1) passes and (2) or (3)
fails, the bug is in that gateway's integration/permission/deployment.

### `scripts/verify_teardown.py`
Read-only check, run after `terraform destroy`: confirms the Lambda function,
both REST APIs (edge-optimized and regional), and IAM role no longer exist
via boto3. Does not delete anything.

---

## 7. Build & Deploy Steps

```bash
cd api-gateway/infra
cp terraform.tfvars.example terraform.tfvars   # set aws_region
terraform init
terraform apply

terraform output invoke_url
terraform output invoke_url_regional

curl "$(terraform output -raw invoke_url)?name=CS218"
# {"message": "Hello", "params": {"name": "CS218"}}
curl "$(terraform output -raw invoke_url_regional)?name=CS218"
# {"message": "Hello", "params": {"name": "CS218"}}

python ../scripts/smoke_test.py \
    --invoke-url "$(terraform output -raw invoke_url)" \
    --invoke-url-regional "$(terraform output -raw invoke_url_regional)"
```

Manual verification alternative: a Postman `GET` request to the same URL,
with `name=CS218` under the Params tab.

---

## 8. Teardown

```bash
cd infra
terraform destroy
python ../scripts/verify_teardown.py --region us-east-1
```

No persistent state (no S3 bucket, no DynamoDB table) exists outside
Terraform state, so `terraform destroy` fully removes all billable resources.

---

## 9. Common Failure Modes

| Symptom | Likely cause |
|---|---|
| `403 Forbidden` calling the invoke URL | Missing/incorrect `aws_lambda_permission` source ARN, or stage not deployed after a resource change |
| `502 Bad Gateway` | Lambda handler path wrong (`handler.handler` mismatch) or handler throws before returning a valid `statusCode`/`body` shape |
| Direct Lambda invoke works, HTTP call fails | Problem is in API Gateway config (integration type, method, deployment/stage), not the function |
| `terraform apply` doesn't pick up handler code changes | `source_code_hash` not wired to the zip's hash |
| One gateway works, the other 403s | Each gateway needs its own `aws_lambda_permission` — `apigw_invoke` and `apigw_invoke_regional` are separate statements because their `source_arn`s (different `execution_arn`s) can't be combined into one |
