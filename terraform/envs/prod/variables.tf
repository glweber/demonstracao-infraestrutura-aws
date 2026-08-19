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
}

variable "alarm_email_endpoints" {
  description = "Addresses subscribed to the production alarm topic."
  type        = list(string)
  default     = []
}
