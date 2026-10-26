# Create separate private image repositories for the ingestion API and worker.
module "ecr" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "~> 3.2.0"
  #API that receives network events and sends them to SQS
  #Worker that processes events from SQS
  for_each = toset([
    "atlasops-dev-ingestion",
    "atlasops-dev-worker",
  ])
  repository_name               = each.value
  create_repository_policy      = false
  attach_repository_policy      = false
  repository_encryption_type    = var.encryption_type
  repository_image_scan_on_push = var.image_scan_on_push
  # Development convenience: deleting a repository also deletes any images it contains.
  repository_force_delete       = true
  #Must be one of: `MUTABLE`, `MUTABLE_WITH_EXCLUSION`, `IMMUTABLE`, or `IMMUTABLE_WITH_EXCLUSION`. Defaults to `IMMUTABLE`
  repository_image_tag_mutability = var.image_tag_mutability
  # This retention rule only expires v-prefixed tags; CI commit-SHA tags are not covered.
  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Keep the newest 30 images with tags starting with v",
        selection = {
          tagStatus     = "tagged",
          tagPrefixList = ["v"],
          countType     = "imageCountMoreThan",
          countNumber   = 30
        },
        action = {
          type = "expire"
        }
      }
    ]
  })

  tags = var.resource_tags

}
