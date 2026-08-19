variable "name" {
  description = "Name prefix applied to every resource created by this module."
  type        = string
}

variable "cluster_name" {
  description = "Cluster whose workload logs are collected."
  type        = string
}

variable "log_retention_days" {
  description = "Retention applied to the application log group, in days."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "The value must be one of the retention periods accepted by CloudWatch Logs."
  }
}

variable "error_rate_threshold" {
  description = "Number of error-level records within the evaluation window that raises the alarm."
  type        = number
  default     = 10

  validation {
    condition     = var.error_rate_threshold > 0
    error_message = "A threshold of zero would alarm on any single error and cannot be acted upon."
  }
}

variable "alarm_evaluation_periods" {
  description = "Consecutive periods the threshold must be breached before the alarm fires."
  type        = number
  default     = 2

  validation {
    condition     = var.alarm_evaluation_periods >= 2
    error_message = "At least two periods are required so that a single scrape anomaly does not page anyone."
  }
}

variable "alarm_email_endpoints" {
  description = "Addresses subscribed to the alarm topic. Left empty, the topic is created without subscribers."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags merged into every resource created by this module."
  type        = map(string)
  default     = {}
}
