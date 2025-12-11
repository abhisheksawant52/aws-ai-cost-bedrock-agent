resource "null_resource" "bedrock_agent_bootstrap" {
  # Optional: ensure IAM role/policies are created before the bootstrap runs.
  # depends_on = [
  #   aws_iam_role.bedrock_agent_finops_role,
  #   aws_iam_role_policy_attachment.lambda_cost_email_attach,
  #   aws_iam_role_policy_attachment.lambda_basic_execution,
  # ]

  provisioner "local-exec" {
    interpreter = ["bash", "-lc"]

    command = <<-EOT
      set -e

      REGION="us-east-1"
      AGENT_NAME="aws-cost-finops-agent"
      AGENT_ROLE_ARN="arn:aws:iam::134607809331:role/bedrock-agent-finops-role"
      FOUNDATION_MODEL="amazon.titan-text-express-v1"
      AGENT_ALIAS_NAME="prod"

      # Build the instruction text safely with a here-doc (used for both update & create).
      INSTRUCTION=$(cat << 'EOF'
You are an AWS FinOps Cost Reporting Assistant.

You receive JSON containing AWS month-to-date unblended cost data by service.

Your task is to generate a final, ready-to-send email. terraform 

GREETING RULE
Always use this greeting exactly:
Dear AWS AI Cost Exporter,

OUTPUT REQUIREMENTS
- Output must be plain text only (no markdown, no HTML unless specified).
- Do NOT include JSON or repeat the input data.
- Do NOT use placeholders like [Insert name], [Insert month], etc.
- Do NOT explain your reasoning.
- Do NOT wrap your response in XML or any other tags.

EMAIL STRUCTURE
Your email must follow this structure:

Dear AWS AI Cost Exporter,

[1] Executive summary of the total AWS cost and the date range
[2] Bullet list of the top cost-driving services (max 5)
[3] Observations section (1 short paragraph)
[4] Optimization suggestions (3–5 bullet points)
[5] Closing line

TONE
- Professional and concise
- Avoid technical jargon unless necessary
- Use dollar formatting (e.g., $0.00 USD)

RAW DATA HANDLING
Do NOT include raw cost data inside the AI summary.
The raw block will be appended by the Lambda function automatically.

Your response must be the final email body only.
EOF
)

      echo "Looking for existing Bedrock Agent '$${AGENT_NAME}' in region $${REGION} ..."

      EXISTING_AGENT_ID=$(aws bedrock-agent list-agents \
        --region "$${REGION}" \
        --query "agentSummaries[?agentName=='$${AGENT_NAME}'].agentId | [0]" \
        --output text)

      if [ "$${EXISTING_AGENT_ID}" != "None" ] && [ -n "$${EXISTING_AGENT_ID}" ]; then
        echo "Found existing Agent: $${EXISTING_AGENT_ID}"
        AGENT_ID="$${EXISTING_AGENT_ID}"

        echo "Updating existing agent instruction ..."
        aws bedrock-agent update-agent \
          --region "$${REGION}" \
          --agent-id "$${AGENT_ID}" \
          --instruction "$${INSTRUCTION}"
      else
        echo "No existing agent found. Creating new Agent..."

        AGENT_ID=$(aws bedrock-agent create-agent \
          --region "$${REGION}" \
          --agent-name "$${AGENT_NAME}" \
          --agent-resource-role-arn "$${AGENT_ROLE_ARN}" \
          --foundation-model "$${FOUNDATION_MODEL}" \
          --instruction "$${INSTRUCTION}" \
          --query "agent.agentId" \
          --output text)

        echo "Created Agent ID: $${AGENT_ID}"
      fi

      echo "Preparing Agent $${AGENT_ID} in region $${REGION} ..."

      aws bedrock-agent prepare-agent \
        --region "$${REGION}" \
        --agent-id "$${AGENT_ID}"

      echo "Waiting for agent to reach PREPARED state ..."
      ATTEMPTS=60
      SLEEP_SECONDS=10

      for i in $(seq 1 $${ATTEMPTS}); do
        STATUS=$(aws bedrock-agent get-agent \
          --region "$${REGION}" \
          --agent-id "$${AGENT_ID}" \
          --query "agent.agentStatus" \
          --output text)

        echo "Attempt $${i}: agentStatus = $${STATUS}"

        if [ "$${STATUS}" = "PREPARED" ]; then
          echo "Agent is PREPARED."
          break
        fi

        if [ "$${STATUS}" = "FAILED" ]; then
          echo "Agent entered FAILED state!"
          exit 1
        fi

        if [ $${i} -eq $${ATTEMPTS} ]; then
          echo "Timeout preparing agent."
          exit 1
        fi

        sleep $${SLEEP_SECONDS}
      done

      echo "Checking for existing alias '$${AGENT_ALIAS_NAME}' ..."

      EXISTING_ALIAS_ID=$(aws bedrock-agent list-agent-aliases \
        --region "$${REGION}" \
        --agent-id "$${AGENT_ID}" \
        --query "agentAliasSummaries[?agentAliasName=='$${AGENT_ALIAS_NAME}'].agentAliasId | [0]" \
        --output text)

      if [ "$${EXISTING_ALIAS_ID}" != "None" ] && [ -n "$${EXISTING_ALIAS_ID}" ]; then
        echo "Found existing alias: $${EXISTING_ALIAS_ID}"
        ALIAS_ID="$${EXISTING_ALIAS_ID}"
      else
        echo "Creating alias '$${AGENT_ALIAS_NAME}' ..."

        ALIAS_ID=$(aws bedrock-agent create-agent-alias \
          --region "$${REGION}" \
          --agent-id "$${AGENT_ID}" \
          --agent-alias-name "$${AGENT_ALIAS_NAME}" \
          --query "agentAlias.agentAliasId" \
          --output text)

        echo "Created alias ID: $${ALIAS_ID}"
      fi

      echo "==== BEDROCK AGENT INFO (copy into terraform.tfvars or outputs) ===="
      echo "BEDROCK_AGENT_ID=$${AGENT_ID}"
      echo "BEDROCK_AGENT_ALIAS_ID=$${ALIAS_ID}"
      echo "====================================================================="
    EOT
  }
}
