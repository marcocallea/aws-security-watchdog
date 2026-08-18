import json
import os
import time
from datetime import datetime, timezone

import boto3

TABLE_NAME = os.environ["TABLE_NAME"]
TOPIC_ARN = os.environ["TOPIC_ARN"]
RETENTION_DAYS = int(os.environ.get("RETENTION_DAYS", "90"))

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)
sns = boto3.client("sns")

HIGH_SEVERITY_EVENTS = {"StopLogging", "DeleteTrail", "UpdateTrail"}
IAM_EVENTS = {
    "CreateUser",
    "CreateAccessKey",
    "AttachUserPolicy",
    "AttachRolePolicy",
    "PutUserPolicy",
    "DeleteUser",
}


def is_open_to_world(detail):
    raw = json.dumps(detail.get("requestParameters") or {})
    return "0.0.0.0/0" in raw or "::/0" in raw


def describe_actor(identity):
    if not identity:
        return "sconosciuto"
    actor_type = identity.get("type", "")
    if actor_type == "Root":
        return "ROOT dell'account"
    if identity.get("userName"):
        return f"{actor_type}:{identity['userName']}"
    if identity.get("arn"):
        return identity["arn"]
    return actor_type or "sconosciuto"


def is_root(identity):
    if not identity:
        return False
    if identity.get("type") == "Root":
        return True
    arn = identity.get("arn", "")
    return arn.endswith(":root")


def login_failed(detail):
    response = detail.get("responseElements") or {}
    return response.get("ConsoleLogin") == "Failure"


def assess(detail):
    event_name = detail.get("eventName", "")
    identity = detail.get("userIdentity") or {}

    if event_name in HIGH_SEVERITY_EVENTS:
        return "HIGH", "Modifica alla configurazione di CloudTrail"

    if event_name == "ConsoleLogin":
        if is_root(identity):
            return "HIGH", "Accesso alla console con utente root"
        if login_failed(detail):
            return "MEDIUM", "Tentativo di accesso alla console fallito"
        return "LOW", "Accesso alla console"

    if event_name in IAM_EVENTS:
        return "MEDIUM", "Modifica a utenti, chiavi o policy IAM"

    if event_name.startswith("Authorize") and is_open_to_world(detail):
        return "MEDIUM", "Security group aperto verso internet (0.0.0.0/0)"

    if event_name.startswith(("Authorize", "Revoke")):
        return "LOW", "Modifica alle regole di un security group"

    return "LOW", "Evento monitorato"


def build_item(detail, region, severity, reason):
    occurred_at = detail.get("eventTime") or datetime.now(timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    identity = detail.get("userIdentity") or {}

    item = {
        "event_date": occurred_at[:10],
        "occurred_at": f"{occurred_at}#{detail.get('eventID', '')}",
        "expires_at": int(time.time()) + RETENTION_DAYS * 24 * 3600,
        "severity": severity,
        "reason": reason,
        "event_name": detail.get("eventName", ""),
        "event_source": detail.get("eventSource", ""),
        "actor": describe_actor(identity),
        "actor_type": identity.get("type", ""),
        "source_ip": detail.get("sourceIPAddress", ""),
        "user_agent": (detail.get("userAgent") or "")[:200],
        "region": region,
        "request_id": detail.get("requestID", ""),
        "event_id": detail.get("eventID", ""),
    }

    if detail.get("errorCode"):
        item["error_code"] = detail["errorCode"]

    return {k: v for k, v in item.items() if v != ""}


def build_message(item):
    lines = [
        f"[{item['severity']}] {item['reason']}",
        "",
        f"Evento:    {item.get('event_name', 'n/d')}",
        f"Servizio:  {item.get('event_source', 'n/d')}",
        f"Chi:       {item.get('actor', 'n/d')}",
        f"Quando:    {item.get('occurred_at', '').split('#')[0]}",
        f"Da IP:     {item.get('source_ip', 'n/d')}",
        f"Regione:   {item.get('region', 'n/d')}",
    ]
    if item.get("error_code"):
        lines.append(f"Errore:    {item['error_code']}")
    lines += ["", f"Event ID:  {item.get('event_id', 'n/d')}"]
    return "\n".join(lines)


def handler(event, context):
    detail = event.get("detail") or {}

    if detail.get("readOnly") is True:
        print(f"Ignorato evento readOnly: {detail.get('eventName')}")
        return {"skipped": True}

    severity, reason = assess(detail)
    item = build_item(detail, event.get("region", ""), severity, reason)

    table.put_item(Item=item)

    if severity in ("HIGH", "MEDIUM"):
        sns.publish(
            TopicArn=TOPIC_ARN,
            Subject=f"[{severity}] {item.get('event_name', 'evento AWS')}"[:100],
            Message=build_message(item),
        )

    print(json.dumps({"severity": severity, "event": item.get("event_name")}))
    return {"severity": severity, "stored": True}