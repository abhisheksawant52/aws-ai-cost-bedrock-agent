data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "cost_reporter" {
  function_name = var.lambda_function_name
  role          = aws_iam_role.lambda_role.arn
  runtime       = "python3.11"
  handler       = "lambda_function.lambda_handler"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  timeout     = 120
  memory_size = 512

  depends_on = [
    aws_sesv2_email_identity.cost_report_sender,
    null_resource.bedrock_agent_bootstrap
  ]

  environment {
    variables = {
      COST_EMAIL_TO          = var.cost_email_to
      COST_EMAIL_FROM        = var.cost_email_from
      BEDROCK_AGENT_ID       = var.bedrock_agent_id
      BEDROCK_AGENT_ALIAS_ID = var.bedrock_agent_alias_id
    }
  }
}
