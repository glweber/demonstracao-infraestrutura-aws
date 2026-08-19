output "repository_url" {
  description = "Registry URL used as the image reference prefix in Kubernetes manifests."
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ARN of the repository, for use in IAM policies granting pull access."
  value       = aws_ecr_repository.this.arn
}

output "repository_name" {
  description = "Name of the repository."
  value       = aws_ecr_repository.this.name
}
