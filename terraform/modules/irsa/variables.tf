variable "role_name" {
  description = "Name of the IAM role assumed by the Kubernetes service account."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the IAM OIDC identity provider registered for the cluster."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:oidc-provider/", var.oidc_provider_arn))
    error_message = "A valid IAM OIDC provider ARN is required."
  }
}

variable "oidc_provider_url" {
  description = "Issuer URL of the cluster OIDC provider, without the scheme."
  type        = string

  validation {
    condition     = !startswith(var.oidc_provider_url, "https://")
    error_message = "Supply the issuer host and path only; the scheme must be omitted."
  }
}

variable "namespace" {
  description = "Kubernetes namespace of the service account permitted to assume the role."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.namespace))
    error_message = "The namespace must be a valid RFC 1123 label."
  }
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account permitted to assume the role."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?$", var.service_account_name))
    error_message = "The service account name must be a valid RFC 1123 subdomain."
  }
}

variable "permissions_boundary_arn" {
  description = "Optional permissions boundary capping the effective permissions of the role."
  type        = string
  default     = null
}

variable "policy_arns" {
  description = "ARNs of the managed policies attached to the role."
  type        = list(string)
  default     = []
}

variable "inline_policy_json" {
  description = "Optional inline policy document granting the least privilege the workload requires."
  type        = string
  default     = null
}

variable "max_session_duration_seconds" {
  description = "Ceiling on the lifetime of a session assumed against this role. IAM does not accept a value below one hour; a caller may still request a shorter session."
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration_seconds >= 3600 && var.max_session_duration_seconds <= 43200
    error_message = "IAM accepts a role session duration between 3600 and 43200 seconds."
  }
}

variable "tags" {
  description = "Tags merged into every resource created by this module."
  type        = map(string)
  default     = {}
}
