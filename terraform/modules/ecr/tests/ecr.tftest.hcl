# Unit tests for the container registry module, run against a mocked provider.

mock_provider "aws" {}

variables {
  name = "demonstration-service"
  tags = { Environment = "test" }
}

run "supply_chain_controls_are_enabled_by_default" {
  command = plan

  assert {
    condition     = aws_ecr_repository.this.image_tag_mutability == "IMMUTABLE"
    error_message = "Tags must be immutable so that a deployed reference cannot be repointed."
  }

  assert {
    condition     = aws_ecr_repository.this.image_scanning_configuration[0].scan_on_push
    error_message = "Images must be scanned for vulnerabilities on push."
  }

  assert {
    condition     = aws_ecr_repository.this.force_delete == false
    error_message = "Repositories holding images must not be deletable in a single step."
  }
}

run "aws_managed_encryption_is_used_when_no_key_is_supplied" {
  command = plan

  assert {
    condition     = aws_ecr_repository.this.encryption_configuration[0].encryption_type == "AES256"
    error_message = "Without a customer-managed key the repository must fall back to AES256."
  }
}

run "customer_managed_encryption_is_selected_when_a_key_is_supplied" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:eu-west-1:111122223333:key/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = aws_ecr_repository.this.encryption_configuration[0].encryption_type == "KMS"
    error_message = "Supplying a key must switch the repository to customer-managed encryption."
  }
}

run "lifecycle_policy_expires_untagged_and_bounds_releases" {
  command = plan

  assert {
    condition     = length(jsondecode(aws_ecr_lifecycle_policy.this.policy).rules) == 2
    error_message = "The lifecycle policy must cover untagged images and release retention."
  }

  assert {
    condition     = jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[0].selection.tagStatus == "untagged"
    error_message = "The highest-priority rule must expire untagged images."
  }
}

run "rejects_a_retention_window_without_a_rollback_target" {
  command = plan

  variables {
    retained_release_image_count = 1
  }

  expect_failures = [var.retained_release_image_count]
}
