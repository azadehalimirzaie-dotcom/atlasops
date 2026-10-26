# Alert through SNS when the dead-letter queue contains at least one failed event.
resource "aws_cloudwatch_metric_alarm" "events_dlq" {
  alarm_name = "${var.resource_tags["Project"]}-${var.resource_tags["Environment"]}-events-dlq"
  #The number of messages currently available for retrieval and processing.
  alarm_description = "AtlasOps has failed messages in its events DLQ. Inspect worker logs and DLQ messages"

  metric_name = "ApproximateNumberOfMessagesVisible"
  namespace   = "AWS/SQS"
  period      = 60
  statistic   = "Maximum"

  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  # One breaching one-minute sample triggers the alarm; absent samples do not trigger it.
  treat_missing_data  = "notBreaching"
  evaluation_periods  = 1
  datapoints_to_alarm = 1

  dimensions = {
    QueueName = "${module.sqs.dead_letter_queue_name}"
  }

  # Publish both alarm and recovery transitions to the notification topic.
  alarm_actions = [module.sns_topic.topic_arn]
  ok_actions    = [module.sns_topic.topic_arn]

  tags = var.resource_tags

}
