resource "aws_sesv2_email_identity" "cost_report_sender" {
  email_identity = var.cost_email_from
}
