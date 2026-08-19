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
  description = "Address space allocated to the environment."
  type        = string
  default     = "10.10.0.0/16"
}

variable "kubernetes_version" {
  description = "Minor version of Kubernetes for the control plane."
  type        = string
  default     = "1.31"
}

variable "operator_access_cidrs" {
  description = "Source ranges permitted to reach the public Kubernetes API endpoint. Narrow this to the office or VPN egress addresses."
  type        = list(string)
  default     = ["203.0.113.0/24"]
}
