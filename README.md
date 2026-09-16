# Simple API Gateway → Lambda "Hello"

Reference implementation of the plan in [`Plan.md`](Plan.md). `GET /hello`
is exposed by two independent REST APIs — one EDGE-optimized (the default
endpoint type), one REGIONAL — both fronting the exact same Lambda function,
which returns `{"message":"Hello"}`. Two gateways in front of one function
so their latency can be compared directly against an identical backend.

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

## Repository layout

```
infra/      Terraform root — IAM role, Lambda function, two REST APIs
            (api.tf = EDGE-optimized, api_regional.tf = REGIONAL), deployment/stage each
lambda/     Lambda function source (hello/handler.py) — shared by both gateways
scripts/    boto3 helper scripts, run from the command line, not deployed
```

`terraform apply` packages `lambda/hello/handler.py` into a zip automatically
(via the `archive_file` data source in `infra/lambda.tf`) — you do not need to
run anything by hand before the first deploy.

## 1. Prerequisites

- An AWS account and an IAM user (not root) with programmatic access keys.
  The user needs permission to create/manage: Lambda functions, IAM roles,
  API Gateway REST APIs, and CloudWatch Logs. For a personal account,
  attaching `AdministratorAccess` to this IAM user is the simplest option;
  for a shared account, use an IAM policy scoped to just those permissions
  instead.
- Terraform >= 1.5 ([install guide](https://developer.hashicorp.com/terraform/install))
- Python 3.9+ and `pip`
- AWS CLI (optional but convenient): `pip install awscli`

Configure your credentials once, in the region you intend to use throughout:

```bash
aws configure
# AWS Access Key ID / Secret Access Key / region (e.g. us-east-1) / output format
```

Verify the CLI can see your account before touching Terraform:

```bash
aws sts get-caller-identity
```

## 2. Install Python dependencies for the helper scripts

```bash
cd scripts
pip install -r requirements.txt
cd ..
```

## 3. Deploy the infrastructure

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars if you want a region other than us-east-1

terraform init
terraform plan     # review what will be created
terraform apply    # type "yes" to confirm
```

This creates, in order: an IAM role for the Lambda function, the Lambda
function itself (zipped from `lambda/hello/handler.py`), then **two**
independent REST APIs each with their own `/hello` resource, `GET` method,
`AWS_PROXY` integration to that same Lambda function, permission, and
deployment published under the `prod` stage — one EDGE-optimized
(`api.tf`), one REGIONAL (`api_regional.tf`).

When it finishes, note the outputs:

```bash
terraform output invoke_url
# https://<api-id>.execute-api.<region>.amazonaws.com/prod/hello   (EDGE-optimized)

terraform output invoke_url_regional
# https://<other-api-id>.execute-api.<region>.amazonaws.com/prod/hello   (REGIONAL)

cd ..   # back to the project root - the commands in step 4 run from here
```

## 4. Test it against your AWS account

**Quickest check — curl or a browser:**

```bash
curl "$(terraform -chdir=infra output -raw invoke_url)?name=CS218"
# {"message": "Hello", "params": {"name": "CS218"}}

curl "$(terraform -chdir=infra output -raw invoke_url_regional)?name=CS218"
# {"message": "Hello", "params": {"name": "CS218"}}
```

Any query string parameters on the request are echoed back under `params` —
the handler reads them straight out of the proxy-integration `event`
(`event["queryStringParameters"]`), so no Terraform changes are needed to add
more of them later. Both gateways return byte-identical responses — they're
two front ends for the exact same Lambda function.

**Postman:** create a new `GET` request, paste in either `invoke_url` value,
add a query param (e.g. `name=CS218`) under the Params tab, and hit Send. You
should get HTTP `200` and a JSON body echoing that param back.

**Timing breakdown (curl):** connection-phase timing for each endpoint — DNS
lookup, TCP connect, TLS handshake, time to first byte, and total request
time, plus the HTTP status code. Run against both `invoke_url` and
`invoke_url_regional` to compare EDGE (fronted by CloudFront) against
REGIONAL (no CloudFront hop):

```bash
curl -s -o /dev/null -w "\n===================================\n DNS Lookup:       %{time_namelookup}s\n TCP Connect:      %{time_connect}s\n TLS Handshake:    %{time_appconnect}s\n Time to 1st Byte: %{time_starttransfer}s\n Total Request:    %{time_total}s\n Status Code:      %{http_code}\n===================================\n" "$(terraform -chdir=infra output -raw invoke_url)"

curl -s -o /dev/null -w "\n===================================\n DNS Lookup:       %{time_namelookup}s\n TCP Connect:      %{time_connect}s\n TLS Handshake:    %{time_appconnect}s\n Time to 1st Byte: %{time_starttransfer}s\n Total Request:    %{time_total}s\n Status Code:      %{http_code}\n===================================\n" "$(terraform -chdir=infra output -raw invoke_url_regional)"
```

**Automated smoke test (boto3):** runs five checks — a direct Lambda invoke
with no params (bypasses both API Gateways entirely), an HTTPS call with
`?name=CS218` through each gateway's deployed stage (exercises the full path
in the diagram above, once per gateway), and the curl timing breakdown above
against each gateway (shelled out from Python, since these are libcurl
connection-phase timers that `urllib` can't produce). If the first check
passes but one HTTP check fails, the bug is in that specific gateway's
configuration, not the function or the other gateway.

```bash
cd scripts
python smoke_test.py \
    --invoke-url "$(terraform -chdir=../infra output -raw invoke_url)" \
    --invoke-url-regional "$(terraform -chdir=../infra output -raw invoke_url_regional)" \
    --region us-east-1
cd ..
```

Expected output:

```
1. Invoking Lambda function directly via boto3 (no params)...
   PASS - {'message': 'Hello', 'params': {}}
2. Calling edge-optimized endpoint: https://<api-id>.execute-api.us-east-1.amazonaws.com/prod/hello?name=CS218
   PASS - {'message': 'Hello', 'params': {'name': 'CS218'}}
3. Calling regional endpoint: https://<other-api-id>.execute-api.us-east-1.amazonaws.com/prod/hello?name=CS218
   PASS - {'message': 'Hello', 'params': {'name': 'CS218'}}
4. Timing breakdown for edge-optimized endpoint (https://<api-id>.execute-api.us-east-1.amazonaws.com/prod/hello)...

===================================
 DNS Lookup:       0.022s
 TCP Connect:      0.055s
 TLS Handshake:    0.354s
 Time to 1st Byte: 0.377s
 Total Request:    0.379s
 Status Code:      200
===================================

5. Timing breakdown for regional endpoint (https://<other-api-id>.execute-api.us-east-1.amazonaws.com/prod/hello)...

===================================
 DNS Lookup:       0.020s
 TCP Connect:      0.048s
 TLS Handshake:    0.301s
 Time to 1st Byte: 0.318s
 Total Request:    0.319s
 Status Code:      200
===================================

All checks passed.
```

## 5. Iterating on the Lambda code

`terraform apply` re-zips and redeploys automatically whenever
`lambda/hello/handler.py` changes (Terraform detects the change via
`source_code_hash`). For faster iteration without a full `terraform apply`,
you can push code changes straight to the live function with boto3:

```bash
cd scripts
python build_lambda.py --deploy --region us-east-1
cd ..
```

## 6. Troubleshooting

| Symptom | Likely cause |
|---|---|
| `403 Forbidden` calling the invoke URL | Missing/incorrect Lambda permission, or the API wasn't redeployed after a resource change — re-run `terraform apply` |
| `502 Bad Gateway` | Lambda handler throws, or the handler path (`handler.handler`) doesn't match the file/function name |
| Direct Lambda invoke passes, HTTP call fails | The bug is in API Gateway (method, integration, permission, or stage), not the function |
| One gateway (`invoke_url` or `invoke_url_regional`) works, the other 403s | Each gateway has its own `aws_lambda_permission` (`apigw_invoke` / `apigw_invoke_regional`) — check the one matching the failing gateway; they can't share a single permission statement |
| `terraform apply` doesn't pick up a handler code change | Confirm you edited `lambda/hello/handler.py` and re-ran `terraform apply` — `source_code_hash` should trigger a redeploy automatically. It redeploys **both** gateways, since they share the one Lambda function |
| `AccessDenied` during `terraform apply` | The IAM user configured in `aws configure` lacks permission for one of: `lambda:*`, `apigateway:*`, `iam:CreateRole`/`PutRolePolicy`/`PassRole`, `logs:*` |

## 7. Tear down

Remove every resource this project created so nothing keeps running in your
account:

```bash
cd infra
terraform destroy   # type "yes" to confirm
cd ..
```

There's no S3 bucket or database involved, so `terraform destroy` fully
cleans up — no manual console steps needed afterward.

**Optional — confirm nothing was left behind.** This doesn't delete
anything; it just checks via boto3 that the Lambda function, both REST
APIs, and IAM role are all gone:

```bash
cd scripts
python verify_teardown.py --region us-east-1
cd ..
```

```
gone - Lambda function 'hello-function'
gone - REST API 'hello-api'
gone - REST API 'hello-api-regional'
gone - IAM role 'hello-lambda-exec-role'

Teardown complete - nothing left behind.
```

If anything reports `STILL EXISTS`, re-run `terraform destroy` from `infra/`
— the state file still knows about it.

## Cost

Lambda (1M requests/month) is part of AWS's Always Free tier and is shared
by both gateways — it's one function either way, not double the invocations
per request. API Gateway REST API (1M calls/month **per API**) is free only
within an account's 12-month new-customer window; running two REST APIs
means two separate 1M-call allowances, not half of one shared allowance. At
the handful of manual/smoke-test calls this project generates, expect
effectively $0 either way — but run `terraform destroy` when you're done so
nothing is left running.
