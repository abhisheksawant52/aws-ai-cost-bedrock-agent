import os
import json
import uuid
import boto3
import datetime as dt
from decimal import Decimal

ce = boto3.client("ce")
ses = boto3.client("ses")
bedrock_agent_runtime = boto3.client("bedrock-agent-runtime")


def get_month_to_date_cost_by_service():
    today = dt.date.today()
    start = today.replace(day=1).isoformat()
    end = today.isoformat()

    resp = ce.get_cost_and_usage(
        TimePeriod={"Start": start, "End": end},
        Granularity="MONTHLY",
        Metrics=["UnblendedCost"],
        GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
    )

    groups = resp["ResultsByTime"][0]["Groups"]

    services = []
    for g in groups:
        amount = g["Metrics"]["UnblendedCost"]["Amount"]
        unit = g["Metrics"]["UnblendedCost"]["Unit"]
        services.append(
            {
                "service": g["Keys"][0],
                "amount": str(amount),
                "unit": unit,
            }
        )

    total = sum(Decimal(s["amount"]) for s in services) if services else Decimal("0")
    currency = services[0]["unit"] if services else "USD"

    return {
        "start": start,
        "end": end,
        "currency": currency,
        "total_amount": str(total),
        "services": services,
    }


def summarize_costs_with_bedrock_agent(cost_data: dict) -> str:
    agent_id = os.environ["BEDROCK_AGENT_ID"]
    agent_alias_id = os.environ["BEDROCK_AGENT_ALIAS_ID"]

    input_text = (
        "Here is AWS month-to-date unblended cost data in JSON. "
        "Please generate the cost summary email according to your configured instructions.\n\n"
        f"{json.dumps(cost_data, indent=2)}"
    )

    session_id = str(uuid.uuid4())

    response = bedrock_agent_runtime.invoke_agent(
        agentId=agent_id,
        agentAliasId=agent_alias_id,
        sessionId=session_id,
        inputText=input_text,
    )

    completion_text = []
    for event in response.get("completion", []):
        chunk = event.get("chunk")
        if chunk and "bytes" in chunk:
            completion_text.append(chunk["bytes"].decode("utf-8"))

    return "".join(completion_text).strip() if completion_text else ""


def format_raw_numbers_block(cost_data: dict) -> str:
    lines = []
    lines.append(f"Time range: {cost_data['start']} to {cost_data['end']}")
    lines.append(f"Total: {cost_data['total_amount']} {cost_data['currency']}")
    lines.append("")
    lines.append("Per-service breakdown (unblended):")

    sorted_services = sorted(
        cost_data["services"],
        key=lambda s: Decimal(s["amount"]),
        reverse=True,
    )

    for s in sorted_services:
        lines.append(f"- {s['service']}: {s['amount']} {s['unit']}")

    return "\n".join(lines)


def send_email_via_ses(to_email: str, from_email: str, subject: str, body_text: str):
    ses.send_email(
        Source=from_email,
        Destination={"ToAddresses": [to_email]},
        Message={
            "Subject": {"Data": subject},
            "Body": {
                "Text": {"Data": body_text},
            },
        },
    )


def lambda_handler(event, context):
    to_email = os.environ.get("COST_EMAIL_TO")
    from_email = os.environ.get("COST_EMAIL_FROM")

    if not to_email or not from_email:
        raise ValueError(
            "COST_EMAIL_TO and COST_EMAIL_FROM environment variables must be set."
        )

    cost_data = get_month_to_date_cost_by_service()
    ai_summary = summarize_costs_with_bedrock_agent(cost_data)
    raw_block = format_raw_numbers_block(cost_data)

    email_body = f"""AWS Monthly Cost Report

AI Summary:
{ai_summary}

-----------------------------
Raw Cost Data
-----------------------------
{raw_block}
"""

    subject = f"AWS Cost Report {cost_data['start']} to {cost_data['end']}"

    send_email_via_ses(
        to_email=to_email,
        from_email=from_email,
        subject=subject,
        body_text=email_body,
    )

    return {
        "statusCode": 200,
        "body": json.dumps({"message": "Cost report email sent."}),
    }
