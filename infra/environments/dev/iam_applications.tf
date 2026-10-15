locals {
  application_namespace = "atlasops"
}
#For IRSA, the trust policy is identical every time. Only two values change:
# Trust policies: identify which Kubernetes service account
# can assume each application's IAM role.
data "aws_iam_policy_document" "application_trust" {
  for_each = toset(["ingestion", "worker"])

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values = [
        "system:serviceaccount:${local.application_namespace}:${each.key}" # ← only this changes
      ]
    }
  }
}

# One IAM role for each application.
resource "aws_iam_role" "application" {
  for_each = toset(["ingestion", "worker"])

  name = "${var.resource_tags["Project"]}-${var.resource_tags["Environment"]}-${each.key}"

  assume_role_policy = data.aws_iam_policy_document.application_trust[each.key].json

  tags = var.resource_tags
}

# Ingestion: send events to our queue.
resource "aws_iam_role_policy" "ingestion" {
  name = "send-events"
  role = aws_iam_role.application["ingestion"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SendEvents"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = module.sqs.queue_arn
      }
    ]
  })
}

# Worker: consume events and store them in DynamoDb Table.
resource "aws_iam_role_policy" "worker" {
  name = "process-events"
  role = aws_iam_role.application["worker"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ConsumeEvents"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage"
        ]
        Resource = module.sqs.queue_arn
      },
      {
        Sid      = "StoreEvents"
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:UpdateItem"]
        Resource = module.dynamodb_table.table_arn
      }
    ]
  })
}


#give the worker permission to publish alerts
resource "aws_iam_role_policy" "worker_notifications" {
  name = "publish-critical-alerts"
  role = aws_iam_role.application["worker"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "PublishCriticalAlerts"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = module.sns_topic.topic_arn
      }
    ]
  })
}