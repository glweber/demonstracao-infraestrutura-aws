output "role_arn" {
  description = "ARN of the role. Annotate the service account with eks.amazonaws.com/role-arn set to this value."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the role."
  value       = aws_iam_role.this.name
}

output "service_account_subject" {
  description = "OIDC subject the trust policy is bound to."
  value       = local.subject
}
