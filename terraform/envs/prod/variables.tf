variable "region" {
  description = "AWS region hosting the environment."
  type        = string
  default     = "eu-west-1"
}

variable "project" {
  description = "Project identifier propagated to every resource tag."
  type        = string
  default     = "demonstration-platform"
}

variable "owner" {
  description = "Team accountable for the environment, propagated to every resource tag."
  type        = string
  default     = "platform-engineering"
}

variable "vpc_cidr" {
  description = "Address space allocated to the environment. Distinct from every other environment so that the networks can be peered without renumbering."
  type        = string
  default     = "10.20.0.0/16"
}

variable "kubernetes_version" {
  description = "Minor version of Kubernetes for the control plane."
  type        = string
  default     = "1.31"
}

variable "operator_access_cidrs" {
  description = "Source ranges permitted to reach the public Kubernetes API endpoint."
  type        = list(string)
  default     = ["203.0.113.0/24"]
  validation {
    condition     = length(var.operator_access_cidrs) > 0
    error_message = "At least one source range must be permitted, otherwise the endpoint is unreachable."
  }

  # Validated here as well as in the eks module. The module is the enforcement point;
  # repeating the rule at the environment boundary means the operator editing
  # terraform.tfvars is told immediately, at the line they changed.
  validation {
    condition     = !contains(var.operator_access_cidrs, "0.0.0.0/0")
    error_message = "The Kubernetes API endpoint must not be exposed to the whole internet."
  }

  validation {
    condition     = alltrue([for cidr in var.operator_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Every entry must be a valid CIDR block."
  }

}

variable "alarm_email_endpoints" {
  description = "Addresses subscribed to the production alarm topic."
  type        = list(string)
  default     = []
}
