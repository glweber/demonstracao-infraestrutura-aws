variable "name" {
  description = "Name prefix applied to every resource created by this module."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.name))
    error_message = "The name must be lowercase alphanumeric with hyphens, 3 to 32 characters long."
  }
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block allocated to the VPC. A /16 leaves room for the /20 subnets derived from it."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "The vpc_cidr must be a valid IPv4 CIDR block of prefix length /20 or shorter."
  }
}

variable "availability_zones" {
  description = "Availability zones to spread the subnets across. Three zones are required for a quorum-tolerant control plane."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2 && length(var.availability_zones) <= 6
    error_message = "Between two and six availability zones must be supplied; three is the recommended default."
  }
}

variable "single_nat_gateway" {
  description = "Route every private subnet through one NAT gateway. Reduces cost in non-production environments at the expense of zonal redundancy."
  type        = bool
  default     = false
}

variable "flow_log_retention_days" {
  description = "Retention applied to the VPC flow log group, in days."
  type        = number
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_log_retention_days)
    error_message = "The value must be one of the retention periods accepted by CloudWatch Logs."
  }
}

variable "cluster_name" {
  description = "EKS cluster the subnets serve. Used for the subnet discovery tags read by the AWS Load Balancer Controller."
  type        = string
}

variable "tags" {
  description = "Tags merged into every resource created by this module."
  type        = map(string)
  default     = {}
}
