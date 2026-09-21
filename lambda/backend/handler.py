import json
import os

import boto3

TABLE_NAME = os.environ["TABLE_NAME"]
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)


def handler(event, context):
    path_params = event.get("pathParameters") or {}
    employee_id = path_params.get("id")

    if not employee_id:
        return _response(400, {"error": "Missing employee id in path"})

    result = table.get_item(Key={"EmployeeID": employee_id})
    item = result.get("Item")

    if not item:
        return _response(404, {"error": f"No employee found for ID '{employee_id}'"})

    body = {
        "employeeId": item["EmployeeID"],
        "name": item["Name"],
        "salary": int(item["Salary"]),
        "dateOfJoin": item["DateOfJoin"],
        "description": item["Description"],
    }
    return _response(200, body)


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
