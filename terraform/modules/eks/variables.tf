variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,99}$", var.cluster_name))
    error_message = "The cluster name must satisfy the naming rules imposed by Amazon EKS."
  }
}

variable "kubernetes_version" {
  description = "Minor version of Kubernetes for the control plane."
  type        = string

  validation {
    condition     = can(regex("^1\\.(3[0-9]|[4-9][0-9])$", var.kubernetes_version))
    error_message = "Supply a supported minor version such as 1.31; patch versions are managed by EKS."
  }
}

variable "subnet_ids" {
  description = "Private subnets hosting the control plane network interfaces and the worker nodes."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "The control plane requires subnets in at least two availability zones."
  }
}

variable "endpoint_public_access" {
  description = "Expose the Kubernetes API endpoint to the internet. Disable it where operators reach the cluster over private connectivity."
  type        = bool
  default     = true
}

variable "endpoint_public_access_cidrs" {
  description = "Source ranges permitted to reach the public API endpoint. The default is deliberately absent so that an explicit decision is recorded."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.endpoint_public_access_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Every entry must be a valid CIDR block."
  }

  # Cross-variable validation prevents the most consequential misconfiguration this
  # module can produce: an API server reachable from the whole internet by default.
  validation {
    condition     = !var.endpoint_public_access || length(var.endpoint_public_access_cidrs) > 0
    error_message = "Enabling public API access requires an explicit list of permitted source ranges."
  }

  validation {
    condition     = !contains(var.endpoint_public_access_cidrs, "0.0.0.0/0")
    error_message = "The API server endpoint must not be exposed to 0.0.0.0/0."
  }
}

variable "node_instance_types" {
  description = "Instance types offered to the managed node group, in order of preference."
  type        = list(string)
  default     = ["t3.large"]

  validation {
    condition     = length(var.node_instance_types) > 0
    error_message = "At least one instance type must be offered."
  }
}

variable "node_capacity_type" {
  description = "Purchasing model for the node group."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "The capacity type must be either ON_DEMAND or SPOT."
  }
}

variable "node_desired_size" {
  description = "Number of nodes the group is scaled to on creation."
  type        = number
  default     = 3
}

variable "node_min_size" {
  description = "Lower bound on the size of the node group."
  type        = number
  default     = 3
}

variable "node_max_size" {
  description = "Upper bound on the size of the node group."
  type        = number
  default     = 6
}

variable "node_disk_size_gb" {
  description = "Size of the encrypted root volume attached to each node, in gibibytes."
  type        = number
  default     = 50

  validation {
    condition     = var.node_disk_size_gb >= 20
    error_message = "A node requires at least 20 GiB for the container runtime and image cache."
  }
}

variable "control_plane_log_retention_days" {
  description = "Retention applied to the control plane log group, in days."
  type        = number
  default     = 90
}

variable "tags" {
  description = "Tags merged into every resource created by this module."
  type        = map(string)
  default     = {}
}
