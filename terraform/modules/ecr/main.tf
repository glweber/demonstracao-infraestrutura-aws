# Container registry for the workload image.
#
# Two properties matter more than any other here. Tags are immutable, so a
# deployed tag can never be repointed at different content after the fact, which is
# what makes an image reference in a manifest an auditable artefact. And images are
# scanned on push, so a vulnerable layer is reported at build time rather than
# discovered in the cluster.

locals {
  tags = merge(var.tags, {
    "Name"      = var.name
    "Module"    = "ecr"
    "ManagedBy" = "terraform"
  })
}

resource "aws_ecr_repository" "this" {
  name = var.name

  # Immutability is the control that makes a tag a reliable identifier. Without it a
  # rollback to a known-good tag can silently retrieve different content.
  image_tag_mutability = "IMMUTABLE"

  force_delete = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = var.kms_key_arn == null ? "AES256" : "KMS"
    kms_key         = var.kms_key_arn
  }

  tags = local.tags
}

# Registries accumulate cost silently. Untagged layers left by rebuilt tags are
# expired quickly, while a bounded window of release images is retained so that a
# rollback target always exists.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_image_expiry_days} days."
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Retain the most recent ${var.retained_release_image_count} release images."
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = var.retained_release_image_count
        }
        action = { type = "expire" }
      },
    ]
  })
}
