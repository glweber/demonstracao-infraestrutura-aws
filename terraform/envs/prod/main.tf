# Production environment.
#
# Identical in topology to development and divergent only where availability,
# durability or exposure demands it. Every divergence is stated at the point it
# occurs, so that a reviewer can confirm the trade-off rather than infer it.

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  environment  = "prod"
  name         = "${var.project}-${local.environment}"
  cluster_name = "${var.project}-${local.environment}"

  availability_zones = slice(sort(data.aws_availability_zones.available.names), 0, 3)
}

module "network" {
  source = "../../modules/network"

  name               = local.name
  vpc_cidr           = var.vpc_cidr
  availability_zones = local.availability_zones
  cluster_name       = local.cluster_name

  # One NAT gateway per zone. The cost is accepted so that losing a zone removes
  # capacity without severing egress for the zones that remain.
  single_nat_gateway = false

  # Flow logs are evidence during an investigation, so production retains them for
  # a full quarter rather than the month kept in development.
  flow_log_retention_days = 90
}

module "eks" {
  source = "../../modules/eks"

  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version
  subnet_ids         = module.network.private_subnet_ids

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.operator_access_cidrs

  node_instance_types = ["m6i.large", "m6a.large"]
  # On-demand capacity. Spot interruption is acceptable in development but not for
  # a workload holding a service level objective.
  node_capacity_type = "ON_DEMAND"
  node_desired_size  = 3
  node_min_size      = 3
  node_max_size      = 9
  node_disk_size_gb  = 100

  control_plane_log_retention_days = 365
}

module "ecr" {
  source = "../../modules/ecr"

  name                         = "demonstration-service"
  untagged_image_expiry_days   = 7
  retained_release_image_count = 50

  # Production images are encrypted with a customer-managed key so that access can
  # be revoked at the key rather than only at the repository policy.
  kms_key_arn = aws_kms_key.artefacts.arn
}

resource "aws_kms_key" "artefacts" {
  description             = "Encrypts container images for ${local.name}."
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.artefacts_key.json
}

data "aws_caller_identity" "current" {}

# An explicit key policy is what allows image access to be revoked at the key rather
# than only at the repository policy. Without one the key falls back to the implicit
# default, which grants the whole account.
data "aws_iam_policy_document" "artefacts_key" {
  # checkov:skip=CKV_AWS_356:A key policy is attached to one key and evaluated only for
  # that key, so "*" denotes the key itself.
  # checkov:skip=CKV_AWS_109:Account root administration is mandatory on a KMS key.
  # checkov:skip=CKV_AWS_111:As above; service access is constrained by principal.
  statement {
    sid       = "AllowAccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid = "AllowRegistryEncryption"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]

    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["ecr.amazonaws.com"]
    }

    # Confines the service to acting on behalf of this account only.
    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_kms_alias" "artefacts" {
  name          = "alias/${local.name}-artefacts"
  target_key_id = aws_kms_key.artefacts.key_id
}

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

  # Production credentials are held for fifteen minutes, the shortest window the
  # service permits, limiting the value of a leaked token.
  max_session_duration_seconds = 900
}

module "observability" {
  source = "../../modules/observability"

  name               = local.name
  cluster_name       = module.eks.cluster_name
  log_retention_days = 365

  error_rate_threshold     = 10
  alarm_evaluation_periods = 2
  alarm_email_endpoints    = var.alarm_email_endpoints
}
