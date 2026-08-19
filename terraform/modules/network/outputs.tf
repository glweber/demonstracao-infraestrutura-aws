output "vpc_id" {
  description = "Identifier of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "IPv4 CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Identifiers of the public subnets, ordered by availability zone."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Identifiers of the private subnets, ordered by availability zone. Node groups and pods are placed here."
  value       = aws_subnet.private[*].id
}

output "public_subnet_cidrs" {
  description = "CIDR blocks derived for the public subnets."
  value       = local.public_subnet_cidrs
}

output "private_subnet_cidrs" {
  description = "CIDR blocks derived for the private subnets."
  value       = local.private_subnet_cidrs
}

output "nat_gateway_ids" {
  description = "Identifiers of the NAT gateways serving the private subnets."
  value       = aws_nat_gateway.this[*].id
}

output "flow_log_group_name" {
  description = "CloudWatch Logs group receiving the VPC flow logs."
  value       = aws_cloudwatch_log_group.flow_logs.name
}
