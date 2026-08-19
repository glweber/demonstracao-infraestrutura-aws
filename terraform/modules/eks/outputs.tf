output "cluster_name" {
  description = "Name of the cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "HTTPS endpoint of the Kubernetes API server."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority bundle used to verify the API server."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Security group created by EKS for control plane to node communication."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider. Supply this to the irsa module."
  value       = aws_iam_openid_connect_provider.this.arn
}

output "oidc_provider_url" {
  description = "Issuer URL of the OIDC provider without its scheme, as required in IAM trust conditions."
  value       = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
}

output "node_role_arn" {
  description = "ARN of the IAM role assumed by the worker nodes."
  value       = aws_iam_role.node.arn
}

output "secrets_kms_key_arn" {
  description = "ARN of the key encrypting Kubernetes secrets at rest."
  value       = aws_kms_key.secrets.arn
}

output "control_plane_log_group_name" {
  description = "CloudWatch Logs group receiving the control plane logs, including the audit trail."
  value       = aws_cloudwatch_log_group.control_plane.name
}
