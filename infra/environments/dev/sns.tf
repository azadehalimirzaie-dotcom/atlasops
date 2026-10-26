# Create the shared alert topic for critical events and dead-letter-queue alarms.
module "sns_topic" {
  source  = "terraform-aws-modules/sns/aws"
  version = "~> 7.2.0"

  name                = "${var.resource_tags["Project"]}-${var.resource_tags["Environment"]}-sns-topic"
  create_subscription = true
  # Each recipient must confirm the AWS email subscription before receiving notifications.
  subscriptions = {
    for name, email in var.alert_emails : name => {
      protocol = "email"
      endpoint = email
    }
  }
  region = var.region
  tags   = var.resource_tags

  # Allow CloudWatch to publish only from the configured account and specific DLQ alarm.
  topic_policy_statements = {
    cloudwatch_alarms = {
      actions = ["sns:publish"]
      effect  = "Allow"
      principals = [{
        type        = "Service"
        identifiers = ["cloudwatch.amazonaws.com"]
      }]
      condition = [{
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = ["483598626808"]
        },
        {
          test     = "ArnEquals"
          variable = "aws:SourceArn"
          values   = ["arn:aws:cloudwatch:${var.region}:483598626808:alarm:${var.resource_tags["Project"]}-${var.resource_tags["Environment"]}-events-dlq"]
      }]
    }
  }
}