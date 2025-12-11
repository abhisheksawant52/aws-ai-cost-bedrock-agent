import os
import json
import uuid
import boto3
import datetime as dt
from decimal import Decimal
from botocore.exceptions import ClientError

ce = boto3.client("ce")
ses = boto3.client("ses")
bedrock_agent_runtime = boto3.client("bedrock-agent-runtime")


def get_month_to_date_cost_by_service():
    today = dt.date.today()
    start = today.replace(day=1).isoformat()
    end = today.isoformat()

    print(f"DEBUG Fetching cost data for period {start} → {end}")

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

    cost_data = {
        "start": start,
        "end": end,
        "currency": currency,
        "total_amount": str(total),
        "services": services,
    }

    print(f"DEBUG Cost data collected: {json.dumps(cost_data)}")
    return cost_data


def summarize_costs_with_bedrock_agent(cost_data: dict) -> str:
    agent_id = os.environ["BEDROCK_AGENT_ID"]
    agent_alias_id = os.environ["BEDROCK_AGENT_ALIAS_ID"]
    region = os.environ.get("AWS_REGION")

    print(
        f"DEBUG Invoking Bedrock Agent → AgentId={agent_id}, AliasId={agent_alias_id}, Region={region}"
    )

    session_id = str(uuid.uuid4())
    print(f"DEBUG Bedrock session_id={session_id}")

    # Tell the agent explicitly that we want HTML
    input_text = (
        "You will receive AWS month-to-date unblended cost data in JSON format.\n"
        "Using your configured instructions, generate a professional HTML email body summarizing the costs.\n\n"
        "Here is the JSON data:\n\n"
        f"{json.dumps(cost_data, indent=2)}"
    )

    try:
        response = bedrock_agent_runtime.invoke_agent(
            agentId=agent_id,
            agentAliasId=agent_alias_id,
            sessionId=session_id,
            inputText=input_text,
        )
    except ClientError as e:
        print(f"ERROR Bedrock invoke_agent failed: {e}")
        raise

    completion_text = []
    for event in response.get("completion", []):
        chunk = event.get("chunk")
        if chunk and "bytes" in chunk:
            completion_text.append(chunk["bytes"].decode("utf-8"))

    ai_html = "".join(completion_text).strip()
    print(f"DEBUG Bedrock HTML (first 400 chars): {ai_html[:400]}")
    return ai_html


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


def build_html_email(ai_html_body: str, raw_block: str) -> str:
    """
    Wrap the agent's HTML fragment into a full HTML email with some simple styling
    and a 'Raw Data' section below.
    """
    # Escape raw block for HTML <pre> (basic replace)
    raw_block_escaped = (
        raw_block.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
    )

    html = f"""<!DOCTYPE html>
<html>
  <head>
    <meta charset="UTF-8" />
    <title>AWS Monthly Cost Report</title>
  </head>
  <body style="font-family: Arial, sans-serif; background-color: #f5f5f5; margin: 0; padding: 20px;">
    <div style="max-width: 800px; margin: 0 auto; background: #ffffff; border-radius: 8px; padding: 20px; box-shadow: 0 2px 6px rgba(0,0,0,0.08);">
      {ai_html_body}

      <hr style="margin: 24px 0; border: none; border-top: 1px solid #e0e0e0;" />

      <h3 style="margin-top: 0;">Raw Cost Data</h3>
      <p style="font-size: 13px; color: #555;">
        The following section contains the raw month-to-date unblended cost breakdown:
      </p>
      <pre style="background: #fafafa; border-radius: 6px; padding: 12px; border: 1px solid #eee; font-size: 12px; overflow-x: auto;">
{raw_block_escaped}
      </pre>
    </div>
  </body>
</html>
"""
    return html


def send_email_via_ses_html(to_email: str, from_email: str, subject: str, html_body: str):
    print(
        f"DEBUG SES sending HTML mail: FROM={from_email} TO={to_email} SUBJECT=\"{subject}\""
    )

    try:
        resp = ses.send_email(
            Source=from_email,
            Destination={"ToAddresses": [to_email]},
            Message={
                "Subject": {"Data": subject},
                "Body": {
                    "Html": {"Data": html_body}
                },
            },
        )
        print(f"DEBUG SES send_email response: {resp}")
        return resp
    except ClientError as e:
        print(f"ERROR SES send_email failed: {e}")
        raise


def lambda_handler(event, context):
    print("DEBUG Lambda invoked")
    print(f"DEBUG Incoming event: {json.dumps(event)}")

    to_email = os.environ.get("COST_EMAIL_TO")
    from_email = os.environ.get("COST_EMAIL_FROM")

    print(
        f"DEBUG Env Vars → COST_EMAIL_FROM={from_email}, COST_EMAIL_TO={to_email}"
    )

    if not to_email or not from_email:
        raise ValueError(
            "COST_EMAIL_TO and COST_EMAIL_FROM environment variables must be set."
        )

    # 1. Cost data
    cost_data = get_month_to_date_cost_by_service()

    # 2. HTML summary from Bedrock agent
    ai_html_body = summarize_costs_with_bedrock_agent(cost_data)

    # 3. Raw block
    raw_block = format_raw_numbers_block(cost_data)

    # 4. Build final HTML email
    html_body = build_html_email(ai_html_body, raw_block)

    subject = f"AWS Monthly Cost Report {cost_data['start']} to {cost_data['end']}"
    print(f"DEBUG Final email subject: {subject}")

    # 5. Send as HTML
    send_email_via_ses_html(
        to_email=to_email,
        from_email=from_email,
        subject=subject,
        html_body=html_body,
    )

    print("DEBUG Lambda completed successfully")

    return {
        "statusCode": 200,
        "body": json.dumps({"message": "Cost report HTML email sent."}),
    }
