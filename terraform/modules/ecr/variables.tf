variable "name" {
  description = "Repository name. Conventionally the service name, optionally namespaced with a slash."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]{1,255}$", var.name))
    error_message = "The repository name must satisfy the naming rules imposed by Amazon ECR."
  }
}

variable "untagged_image_expiry_days" {
  description = "Number of days after which untagged images are expired by the lifecycle policy."
  type        = number
  default     = 7

  validation {
    condition     = var.untagged_image_expiry_days >= 1 && var.untagged_image_expiry_days <= 365
    error_message = "The expiry window must be between 1 and 365 days."
  }
}

variable "retained_release_image_count" {
  description = "Number of release-tagged images retained before the oldest are expired."
  type        = number
  default     = 30

  validation {
    condition     = var.retained_release_image_count >= 3
    error_message = "At least three release images must be retained so that a rollback target always exists."
  }
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key used to encrypt the repository. When null, the AWS-managed key is used."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags merged into every resource created by this module."
  type        = map(string)
  default     = {}
}
