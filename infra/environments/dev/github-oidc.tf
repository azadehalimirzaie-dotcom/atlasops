resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  tags = var.resource_tags
}

resource "aws_iam_role" "github_actions" {
  name = "${var.resource_tags["Project"]}-${var.resource_tags["Environment"]}-github-actions"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::483598626808:oidc-provider/token.actions.githubusercontent.com"
        }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:sub" = "repo:azadehalimirzaie-dotcom/atlasops:ref:refs/heads/main"
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"

          }
        },
    }]
  })

  tags = var.resource_tags
}

resource "aws_iam_role_policy" "github_ecr_push" {
  name = "push-atlas-images"
  role = aws_iam_role.github_actions.name

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "AuthenthicatetoECR"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Sid = "AllowPushingAtlasImages"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:BatchGetImage"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:ecr:${var.region}:483598626808:repository/${var.resource_tags["Project"]}-${var.resource_tags["Environment"]}-ingestion"
        Resource = "arn:aws:ecr:${var.region}:483598626808:repository/${var.resource_tags["Project"]}-${var.resource_tags["Environment"]}-worker"
      }
    ]
  })
}


