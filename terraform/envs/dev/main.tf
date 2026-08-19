# Development environment.
#
# The topology matches production so that a change is exercised against the same
# shape it will meet later. The differences are confined to capacity and to two
# deliberate cost trade-offs, each recorded below: a single NAT gateway and spot
# capacity. Neither is appropriate for production, and prod overrides both.

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  environment  = "dev"
  name         = "${var.project}-${local.environment}"
  cluster_name = "${var.project}-${local.environment}"

  # Three zones, taken in a stable order so that a change in the API response cannot
  # renumber the subnets and force their replacement.
  availability_zones = slice(sort(data.aws_availability_zones.available.names), 0, 3)
}

module "network" {
  source = "../../modules/network"

  name               = local.name
  vpc_cidr           = var.vpc_cidr
  availability_zones = local.availability_zones
  cluster_name       = local.cluster_name

  # One NAT gateway rather than three. Accepted here because a zone failure in a
  # development environment costs nothing but a restart; production keeps one per
  # zone so that a zone loss does not sever egress for the surviving zones.
  single_nat_gateway = true

  flow_log_retention_days = 30
}

module "eks" {
  source = "../../modules/eks"

  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version
  subnet_ids         = module.network.private_subnet_ids

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.operator_access_cidrs

  node_instance_types = ["t3.large"]
  # Spot capacity for interruption-tolerant development workloads.
  node_capacity_type = "SPOT"
  node_desired_size  = 2
  node_min_size      = 2
  node_max_size      = 4
  node_disk_size_gb  = 50

  control_plane_log_retention_days = 30
}

module "ecr" {
  source = "../../modules/ecr"

  name                         = "demonstration-service"
  untagged_image_expiry_days   = 3
  retained_release_image_count = 10
}

# Least-privilege role for the workload. The service reads its own configuration
# objects and nothing else; permissions are granted to this role rather than to the
# node, so no other pod on the same node inherits them.
data "aws_iam_policy_document" "workload" {
  statement {
    sid       = "ReadOwnConfiguration"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${local.name}-configuration/*"]
  }
}

module "workload_irsa" {
  source = "../../modules/irsa"

  role_name            = "${local.name}-workload"
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  namespace            = "demonstration"
  service_account_name = "demonstration-service"
  inline_policy_json   = data.aws_iam_policy_document.workload.json
}

module "observability" {
  source = "../../modules/observability"

  name               = local.name
  cluster_name       = module.eks.cluster_name
  log_retention_days = 30

  # A development environment tolerates a noisier signal than production.
  error_rate_threshold     = 25
  alarm_evaluation_periods = 2
}
