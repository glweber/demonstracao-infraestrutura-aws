output "cluster_name" {
  description = "Name of the cluster, for use with `aws eks update-kubeconfig`."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "HTTPS endpoint of the Kubernetes API server."
  value       = module.eks.cluster_endpoint
}

output "region" {
  description = "Region hosting the environment."
  value       = var.region
}

output "vpc_id" {
  description = "Identifier of the environment VPC."
  value       = module.network.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnets hosting the worker nodes."
  value       = module.network.private_subnet_ids
}

output "image_repository_url" {
  description = "Registry URL to reference in the Kubernetes manifests."
  value       = module.ecr.repository_url
}

output "workload_role_arn" {
  description = "Role annotated onto the workload's service account for IRSA."
  value       = module.workload_irsa.role_arn
}

output "alarm_topic_arn" {
  description = "SNS topic notified by the error rate alarm."
  value       = module.observability.alarm_topic_arn
}

output "kubeconfig_command" {
  description = "Command that configures kubectl against this cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
