# Buffer events in a standard queue and move repeatedly failing messages to a dead-letter queue.
module "sqs" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "~> 5.2.2"

  name       = "${var.resource_tags["Project"]}-${var.resource_tags["Environment"]}-events"
  fifo_queue = false

  message_retention_seconds  = 345600 # 4 days, is the maximum time a message can stay in a queue
  receive_wait_time_seconds  = 20     #Thi turns on long polling: how long a consumer’s ReceiveMessage call waits for messages when the queue is empty.
  visibility_timeout_seconds = 60     #How long a received message stays hidden while a consumer processes it. If not deleted in time, it becomes visible again and is retried
  sqs_managed_sse_enabled    = true

  create_dlq = true
  dlq_name   = "${var.resource_tags["Project"]}-${var.resource_tags["Environment"]}-events-dlq"

  # After five receives without successful deletion, move the message to the DLQ.
  redrive_policy = {
    maxReceiveCount = 5
  }

  dlq_message_retention_seconds  = 1209600 # 14 days
  dlq_receive_wait_time_seconds  = 20
  dlq_visibility_timeout_seconds = 60
  dlq_sqs_managed_sse_enabled    = true

  # The module restricts the DLQ to this module's main queue.
  create_dlq_redrive_allow_policy = true

  tags = var.resource_tags
}
