resource "aws_sns_topic" "change_updates" {
  name              = "${var.project_name}-security-alerts"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.change_updates.arn
  protocol  = "email"
  endpoint  = var.alert_email
}