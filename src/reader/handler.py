import json
import os
from datetime import datetime, timezone

import boto3
from boto3.dynamodb.conditions import Key

TABLE_NAME = os.environ["TABLE_NAME"]
MAX_ITEMS = int(os.environ.get("MAX_ITEMS", "100"))

table = boto3.resource("dynamodb").Table(TABLE_NAME)


def response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, default=str),
    }


def handler(event, context):
    params = event.get("queryStringParameters") or {}
    date = params.get("date") or datetime.now(timezone.utc).strftime("%Y-%m-%d")

    try:
        datetime.strptime(date, "%Y-%m-%d")
    except ValueError:
        return response(400, {"error": "parametro date non valido, atteso YYYY-MM-DD"})

    severity = params.get("severity")

    result = table.query(
        KeyConditionExpression=Key("event_date").eq(date),
        ScanIndexForward=False,
        Limit=MAX_ITEMS,
    )

    items = result.get("Items", [])
    if severity:
        items = [i for i in items if i.get("severity") == severity.upper()]

    return response(200, {"date": date, "count": len(items), "events": items})