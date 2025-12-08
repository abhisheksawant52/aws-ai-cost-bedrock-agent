resource "null_resource" "bedrock_agent_bootstrap" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Looking for existing Bedrock Agent ..."

      EXISTING_AGENT_ID=$(aws bedrock-agent list-agents \
        --region ${var.aws_region} \
        --query "agentSummaries[?agentName=='${var.bedrock_agent_name}'].agentId | [0]" \
        --output text)

      if [ "$EXISTING_AGENT_ID" != "None" ] && [ -n "$EXISTING_AGENT_ID" ]; then
        echo "Found existing Agent: $EXISTING_AGENT_ID"
        AGENT_ID="$EXISTING_AGENT_ID"
      else
        echo "Creating new Agent..."

        AGENT_ID=$(aws bedrock-agent create-agent \
          --region ${var.aws_region} \
          --agent-name "${var.bedrock_agent_name}" \
          --agent-resource-role-arn ${aws_iam_role.bedrock_agent_role.arn} \
          --foundation-model "${var.bedrock_model_id}" \
          --instruction "You are a FinOps / AWS cloud cost assistant. You receive JSON with AWS cost data by service and produce a plain-text, email-ready summary with optimization suggestions." \
          --query "agent.agentId" \
          --output text)

        echo "Created Agent ID: $AGENT_ID"
      fi

      echo "Preparing Agent $AGENT_ID ..."

      aws bedrock-agent prepare-agent \
        --region ${var.aws_region} \
        --agent-id "$AGENT_ID"

      echo "Waiting for agent to reach PREPARED state ..."
      ATTEMPTS=60
      SLEEP_SECONDS=10

      for i in $(seq 1 $ATTEMPTS); do
        STATUS=$(aws bedrock-agent get-agent \
          --region ${var.aws_region} \
          --agent-id "$AGENT_ID" \
          --query "agent.agentStatus" \
          --output text)

        echo "Attempt $i: agentStatus = $STATUS"

        if [ "$STATUS" = "PREPARED" ]; then
          echo "Agent is PREPARED."
          break
        fi

        if [ "$STATUS" = "FAILED" ]; then
          echo "Agent entered FAILED state!"
          exit 1
        fi

        if [ $i -eq $ATTEMPTS ]; then
          echo "Timeout preparing agent."
          exit 1
        fi

        sleep $SLEEP_SECONDS
      done

      echo "Checking for existing alias ..."

      EXISTING_ALIAS_ID=$(aws bedrock-agent list-agent-aliases \
        --region ${var.aws_region} \
        --agent-id "$AGENT_ID" \
        --query "agentAliasSummaries[?agentAliasName=='${var.bedrock_agent_alias_name}'].agentAliasId | [0]" \
        --output text)

      if [ "$EXISTING_ALIAS_ID" != "None" ] && [ -n "$EXISTING_ALIAS_ID" ]; then
        echo "Found existing alias: $EXISTING_ALIAS_ID"
        ALIAS_ID="$EXISTING_ALIAS_ID"
      else
        echo "Creating alias ..."

        ALIAS_ID=$(aws bedrock-agent create-agent-alias \
          --region ${var.aws_region} \
          --agent-id "$AGENT_ID" \
          --agent-alias-name "${var.bedrock_agent_alias_name}" \
          --query "agentAlias.agentAliasId" \
          --output text)

        echo "Created alias ID: $ALIAS_ID"
      fi

      echo "==== BEDROCK AGENT INFO (copy into terraform.tfvars) ===="
      echo "BEDROCK_AGENT_ID=$${AGENT_ID}"
      echo "BEDROCK_AGENT_ALIAS_ID=$${ALIAS_ID}"
      echo "========================================================="
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [
    aws_iam_role.bedrock_agent_role,
    aws_iam_role_policy_attachment.bedrock_agent_policy_attach
  ]
}
