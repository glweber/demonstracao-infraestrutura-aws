# Managed Kubernetes control plane and worker node group.
#
# The configuration encodes four decisions that are difficult to retrofit once a
# cluster carries workloads:
#
#   1. Kubernetes secrets are encrypted with a customer-managed KMS key. Without an
#      encryption provider, secrets are only base64-encoded inside etcd.
#   2. All five control plane log types are shipped to CloudWatch. Audit logs cannot
#      be recovered retrospectively after an incident.
#   3. Nodes join through a launch template that mandates IMDSv2. The single-hop
#      limit prevents a container from reaching the instance metadata service and
#      harvesting the node role's credentials.
#   4. Authentication uses the API access-entry mechanism rather than the aws-auth
#      ConfigMap, so cluster access is declared in code and audited by CloudTrail.

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  tags = merge(var.tags, {
    "Name"      = var.cluster_name
    "Module"    = "eks"
    "ManagedBy" = "terraform"
  })

  # Every control plane log type. Omitting the audit log removes the only record of
  # who called the API server.
  control_plane_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

# ---------------------------------------------------------------------------
# Secret encryption
# ---------------------------------------------------------------------------

resource "aws_kms_key" "secrets" {
  description             = "Envelope encryption key for Kubernetes secrets in ${var.cluster_name}."
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.secrets_key.json

  tags = local.tags
}

data "aws_iam_policy_document" "secrets_key" {
  # checkov:skip=CKV_AWS_356:A key policy is attached to one key and is evaluated only
  # for that key, so "*" denotes the key itself. AWS rejects any other resource value.
  # checkov:skip=CKV_AWS_109:Administrative rights for the account root are mandatory;
  # omitting them renders the key permanently unmanageable.
  # checkov:skip=CKV_AWS_111:As above. Access is constrained by principal instead.
  statement {
    sid       = "AllowAccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # The control plane needs a grant to perform envelope encryption. The permission
  # is granted to the cluster role alone rather than to the service at large.
  statement {
    sid = "AllowClusterRoleEnvelopeEncryption"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "kms:CreateGrant",
    ]

    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.cluster.arn]
    }
  }
}

# The control plane log group carries the audit trail and must be encrypted with a
# key this account controls, not with the service default.
resource "aws_kms_key" "logs" {
  description             = "Encrypts the control plane log group for ${var.cluster_name}."
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.logs_key.json

  tags = local.tags
}

resource "aws_kms_alias" "logs" {
  name          = "alias/${var.cluster_name}-eks-logs"
  target_key_id = aws_kms_key.logs.key_id
}

data "aws_iam_policy_document" "logs_key" {
  # checkov:skip=CKV_AWS_356:Key policies are scoped to the key they are attached to.
  # checkov:skip=CKV_AWS_109:Account root administration is mandatory on a KMS key.
  # checkov:skip=CKV_AWS_111:As above; the grant is constrained by principal and by
  # the encryption context condition below.
  statement {
    sid       = "AllowAccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid = "AllowCloudWatchLogs"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]

    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.region}.amazonaws.com"]
    }

    # Confused-deputy protection: the log service may use the key only on behalf of
    # log groups belonging to this account.
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:*"]
    }
  }
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.cluster_name}-eks-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

# ---------------------------------------------------------------------------
# Control plane
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.cluster_name}-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "cluster" {
  for_each = toset([
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy",
  ])

  role       = aws_iam_role.cluster.name
  policy_arn = each.value
}

# The log group is declared explicitly so that retention and encryption are under
# Terraform's control. Left to EKS, the group is created on first write with
# unlimited retention, which accrues cost indefinitely.
resource "aws_cloudwatch_log_group" "control_plane" {
  # checkov:skip=CKV_AWS_338:Retention is a per-environment decision surfaced as a
  # variable. Production sets 365 days; development accepts 30 deliberately, and the
  # trade-off is recorded at the call site in terraform/envs/dev/main.tf.
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.control_plane_log_retention_days
  kms_key_id        = aws_kms_key.logs.arn

  tags = local.tags
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  enabled_cluster_log_types = local.control_plane_log_types

  access_config {
    # API_AND_CONFIG_MAP would leave the legacy aws-auth ConfigMap authoritative in
    # parallel with access entries, producing two sources of truth for cluster access.
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.secrets.arn
    }
    resources = ["secrets"]
  }

  # checkov:skip=CKV_AWS_39:The public endpoint stays enabled so that operators can
  # reach the API server without a bastion, but variable validation forbids an empty
  # allow-list and rejects 0.0.0.0/0 outright. Set endpoint_public_access to false
  # where private connectivity to the VPC already exists.
  vpc_config {
    subnet_ids = var.subnet_ids

    # Private access is mandatory: it is what allows nodes and operators inside the
    # VPC to reach the API server without traversing the internet.
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access ? var.endpoint_public_access_cidrs : null
  }

  tags = local.tags

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_cloudwatch_log_group.control_plane,
  ]
}

# ---------------------------------------------------------------------------
# OIDC provider, underpinning IRSA
# ---------------------------------------------------------------------------

data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Worker nodes
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.cluster_name}-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json

  tags = local.tags
}

# The node role carries only what the kubelet itself requires. Application
# permissions are granted per workload through IRSA, never here.
resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy",
  ])

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

resource "aws_launch_template" "node" {
  name_prefix = "${var.cluster_name}-node-"

  update_default_version = true

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.node_disk_size_gb
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint = "enabled"
    # IMDSv2 only. Version 1 answers any unauthenticated request from the instance,
    # including one originating inside a container.
    http_tokens = "required"
    # A single hop stops the container network namespace from reaching the metadata
    # service at all, which is what prevents credential theft from the node role.
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { "Name" = "${var.cluster_name}-node" })
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  instance_types = var.node_instance_types
  capacity_type  = var.node_capacity_type

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  # Bounds voluntary disruption during a node roll. Combined with the workload's
  # PodDisruptionBudget, this is what makes a version upgrade non-disruptive.
  update_config {
    max_unavailable_percentage = 25
  }

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  tags = local.tags

  lifecycle {
    # The desired size is owned by the cluster autoscaler once the group is live;
    # reasserting it from state would fight the autoscaler on every apply.
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [aws_iam_role_policy_attachment.node]
}

# ---------------------------------------------------------------------------
# Cluster add-ons
# ---------------------------------------------------------------------------
# Managed add-ons are declared after the node group so that their pods have
# somewhere to schedule on first creation.

resource "aws_eks_addon" "this" {
  for_each = toset(["vpc-cni", "coredns", "kube-proxy", "aws-ebs-csi-driver"])

  cluster_name = aws_eks_cluster.this.name
  addon_name   = each.value

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = local.tags

  depends_on = [aws_eks_node_group.this]
}
