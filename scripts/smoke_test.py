#!/usr/bin/env python3
"""Smoke-test the deployed hello API, both gateways in front of it:

  1. Invoke the Lambda function directly via boto3 — isolates bugs in the
     function code itself, independent of either API Gateway.
  2. Call the EDGE-optimized endpoint over HTTPS — exercises the full path
     from the architecture diagram (Postman/browser -> API Gateway ->
     Lambda) through the default endpoint type (CloudFront in front).
  3. Call the REGIONAL endpoint over HTTPS — the same round-trip, but
     against api_regional.tf's endpoint type (no CloudFront in front),
     sharing the identical Lambda function as (2).
  4. Time the EDGE endpoint with curl's connection-phase breakdown (DNS
     lookup, TCP connect, TLS handshake, time to first byte, total) — these
     are libcurl-level timers, not reproducible through urllib without
     hooking sockets directly, so this shells out to curl.
  5. Time the REGIONAL endpoint the same way, so (4) and (5) can be
     compared directly — that comparison is the reason this project has two
     API Gateways in front of one Lambda function in the first place.

If (1) fails, the bug is in the Lambda handler. If (1) passes but (2) or (3)
fails, the bug is in that specific API Gateway's configuration (method,
integration, permission, or deployment/stage) — the other gateway failing
independently points at that gateway's own wiring, not the shared function.

The endpoint echoes back any query string parameters in the response body
under "params", so this also verifies that round-trip: it calls the direct
invoke with no params (expects "params": {}) and each HTTP endpoint with
?name=CS218 (expects "params": {"name": "CS218"}).

Usage:
    python scripts/smoke_test.py \\
        --invoke-url "$(terraform -chdir=infra output -raw invoke_url)" \\
        --invoke-url-regional "$(terraform -chdir=infra output -raw invoke_url_regional)"
"""
import argparse
import json
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

import boto3

FUNCTION_NAME = "hello-function"

CURL_TIMING_FORMAT = (
    "\n===================================\n"
    " DNS Lookup:       %{time_namelookup}s\n"
    " TCP Connect:      %{time_connect}s\n"
    " TLS Handshake:    %{time_appconnect}s\n"
    " Time to 1st Byte: %{time_starttransfer}s\n"
    " Total Request:    %{time_total}s\n"
    " Status Code:      %{http_code}\n"
    "===================================\n"
)


def test_direct_invoke(step: str, region: str) -> bool:
    print(f"{step}. Invoking Lambda function directly via boto3 (no params)...")
    client = boto3.client("lambda", region_name=region)
    response = client.invoke(FunctionName=FUNCTION_NAME, Payload=b"{}")
    payload = json.loads(response["Payload"].read())
    body = json.loads(payload.get("body", "{}"))

    if payload.get("statusCode") == 200 and body == {"message": "Hello", "params": {}}:
        print(f"   PASS - {body}")
        return True
    print(f"   FAIL - got {payload}")
    return False


def test_http_call(step: str, label: str, invoke_url: str) -> bool:
    url = invoke_url + "?" + urllib.parse.urlencode({"name": "CS218"})
    print(f"{step}. Calling {label} endpoint: {url}")
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            status = resp.status
            body = json.loads(resp.read())
    except urllib.error.URLError as exc:
        print(f"   FAIL - request error: {exc}")
        return False

    expected = {"message": "Hello", "params": {"name": "CS218"}}
    if status == 200 and body == expected:
        print(f"   PASS - {body}")
        return True
    print(f"   FAIL - status={status} body={body}")
    return False


def test_curl_timing(step: str, label: str, invoke_url: str) -> bool:
    print(f"{step}. Timing breakdown for {label} endpoint ({invoke_url})...")
    try:
        result = subprocess.run(
            ["curl", "-s", "-o", "/dev/null", "-w", CURL_TIMING_FORMAT, invoke_url],
            capture_output=True,
            text=True,
            timeout=15,
        )
    except FileNotFoundError:
        print("   SKIP - curl is not installed")
        return True

    print(result.stdout)
    status_line = next((line for line in result.stdout.splitlines() if "Status Code" in line), "")
    if "200" in status_line:
        return True
    print(f"   FAIL - {status_line.strip() or 'curl produced no output'}")
    return False


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--invoke-url",
        required=True,
        help="Full https://.../hello URL for the EDGE-optimized API, e.g. from `terraform output invoke_url`",
    )
    parser.add_argument(
        "--invoke-url-regional",
        required=True,
        help="Full https://.../hello URL for the REGIONAL API, e.g. from `terraform output invoke_url_regional`",
    )
    parser.add_argument("--region", default="us-east-1", help="AWS region of the deployed function")
    args = parser.parse_args()

    results = [
        test_direct_invoke("1", args.region),
        test_http_call("2", "edge-optimized", args.invoke_url),
        test_http_call("3", "regional", args.invoke_url_regional),
        test_curl_timing("4", "edge-optimized", args.invoke_url),
        test_curl_timing("5", "regional", args.invoke_url_regional),
    ]

    if all(results):
        print("\nAll checks passed.")
        sys.exit(0)
    print("\nSome checks failed.")
    sys.exit(1)


if __name__ == "__main__":
    main()
