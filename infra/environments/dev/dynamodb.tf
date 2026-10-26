# Persist processed events in an on-demand DynamoDB table, keyed by event_id.
module "dynamodb_table" {
  source    = "cloudposse/dynamodb/aws"
  version   = "~>0.37.0"
  namespace = var.resource_tags["Project"]
  stage     = var.resource_tags["Environment"]
  name      = "events"

  table_name = "${var.resource_tags["Project"]}-${var.resource_tags["Environment"]}-events"

  # The worker uses a conditional write on this key to avoid storing duplicate events.
  hash_key          = "event_id"
  hash_key_type     = "S"
  enable_autoscaler = false
  billing_mode      = "PAY_PER_REQUEST" # DynamoDB Billing mode. Can be PROVISIONED (Default) or PAY_PER_REQUEST

  # Leave disabled until we configure a stream consumer
  enable_streams = false
  replicas       = []

  # No automatic event expiry configured yet.
  ttl_enabled = false


  tags = var.resource_tags
}

