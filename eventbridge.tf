resource "aws_cloudwatch_event_rule" "cost_report_schedule" {
  name                = "${var.lambda_function_name}-schedule"
  description         = "Schedule for AWS AI cost Bedrock Agent report Lambda"
  schedule_expression = var.schedule_expression
}

resource "aws_cloudwatch_event_target" "cost_report_target" {
  rule      = aws_cloudwatch_event_rule.cost_report_schedule.name
  target_id = "lambda"
  arn       = aws_lambda_function.cost_reporter.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_reporter.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cost_report_schedule.arn
}
