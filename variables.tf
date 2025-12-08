variable "aws_region" {
  description = "AWS region (Bedrock Agents supported)"
  type        = string
  default     = "us-east-1"
}

variable "lambda_function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "aws-ai-cost-bedrock-agent-reporter"
}

variable "cost_email_to" {
  description = "Recipient email for cost reports"
  type        = string
}

variable "cost_email_from" {
  description = "SES-verified sender email"
  type        = string
}

variable "bedrock_model_id" {
  description = "Bedrock foundation model ID for the Agent"
  type        = string
  default     = "anthropic.claude-3-sonnet-20240229-v1:0"
}

variable "bedrock_agent_name" {
  description = "Name for the Bedrock Agent to create"
  type        = string
  default     = "aws-cost-finops-agent"
}

variable "bedrock_agent_alias_name" {
  description = "Name of the Agent alias to create"
  type        = string
  default     = "prod"
}

# These will be wired into Lambda
variable "bedrock_agent_id" {
  description = "Bedrock Agent ID (from bootstrap output)"
  type        = string
}

variable "bedrock_agent_alias_id" {
  description = "Bedrock Agent Alias ID (from bootstrap output)"
  type        = string
}

variable "schedule_expression" {
  description = "EventBridge schedule expression for the Lambda"
  type        = string
  default     = "cron(0 7 1 * ? *)"
}
