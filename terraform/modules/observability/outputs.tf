output "log_group_name" {
  description = "CloudWatch Logs group receiving the workload's container logs."
  value       = aws_cloudwatch_log_group.application.name
}

output "log_group_arn" {
  description = "ARN of the application log group, for use in IAM policies granting write access."
  value       = aws_cloudwatch_log_group.application.arn
}

output "alarm_topic_arn" {
  description = "SNS topic notified when the error rate alarm changes state."
  value       = aws_sns_topic.alarms.arn
}

output "alarm_name" {
  description = "Name of the error rate alarm."
  value       = aws_cloudwatch_metric_alarm.error_rate.alarm_name
}
