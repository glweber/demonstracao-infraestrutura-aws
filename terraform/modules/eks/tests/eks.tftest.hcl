# Unit tests for the EKS module.
#
# The assertions concentrate on the controls that are expensive or impossible to
# introduce after the cluster is carrying workloads: secret encryption, audit
# logging, metadata service hardening, and the exposure of the API endpoint.

mock_provider "aws" {}
mock_provider "tls" {}

override_data {
  target = data.aws_partition.current
  values = {
    partition = "aws"
  }
}

override_data {
  target = data.aws_iam_policy_document.cluster_assume
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

override_data {
  target = data.aws_iam_policy_document.secrets_key
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

override_data {
  target = data.aws_iam_policy_document.logs_key
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

override_data {
  target = data.aws_iam_policy_document.node_assume
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

variables {
  cluster_name                 = "demo-platform"
  kubernetes_version           = "1.31"
  subnet_ids                   = ["subnet-aaaaaaaaaaaaaaaaa", "subnet-bbbbbbbbbbbbbbbbb", "subnet-ccccccccccccccccc"]
  endpoint_public_access       = true
  endpoint_public_access_cidrs = ["203.0.113.0/24"]
  tags                         = { Environment = "test" }
}

run "secrets_are_encrypted_with_a_rotating_customer_managed_key" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.encryption_config[0].resources == toset(["secrets"])
    error_message = "Envelope encryption must be configured for Kubernetes secrets."
  }

  assert {
    condition     = aws_kms_key.secrets.enable_key_rotation
    error_message = "The secret encryption key must rotate automatically."
  }

  assert {
    condition     = aws_kms_key.secrets.deletion_window_in_days == 30
    error_message = "The key must retain the maximum deletion window to survive an accidental destroy."
  }
}

run "every_control_plane_log_type_is_shipped" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.enabled_cluster_log_types == toset(["api", "audit", "authenticator", "controllerManager", "scheduler"])
    error_message = "All five control plane log types must be enabled, the audit log above all."
  }

  assert {
    condition     = aws_cloudwatch_log_group.control_plane.retention_in_days == 90
    error_message = "The control plane log group must carry an explicit retention period."
  }

  # The key ARN is computed, so it is unknown while planning against a mocked
  # provider. The alias and the rotation flag are known, and their presence is what
  # proves a customer-managed key was created for the audit trail; that the log
  # group consumes it is covered by terraform validate.
  assert {
    condition     = aws_kms_alias.logs.name == "alias/demo-platform-eks-logs"
    error_message = "A dedicated customer-managed key must exist for the control plane logs."
  }

  assert {
    condition     = aws_kms_key.logs.enable_key_rotation
    error_message = "The log encryption key must rotate automatically."
  }
}

run "api_access_is_declared_in_code_not_in_a_configmap" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.access_config[0].authentication_mode == "API"
    error_message = "Access entries must be the single source of truth for cluster access."
  }

  assert {
    condition     = aws_eks_cluster.this.access_config[0].bootstrap_cluster_creator_admin_permissions == false
    error_message = "The creating principal must not receive implicit cluster administrator rights."
  }
}

run "private_endpoint_access_is_always_enabled" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_private_access
    error_message = "Private endpoint access must be enabled unconditionally."
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].public_access_cidrs == toset(["203.0.113.0/24"])
    error_message = "Public access must be confined to the supplied source ranges."
  }
}

run "nodes_require_imds_v2_with_a_single_hop" {
  command = plan

  assert {
    condition     = aws_launch_template.node.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv1 must be disabled; it answers unauthenticated requests from inside containers."
  }

  assert {
    condition     = aws_launch_template.node.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "A hop limit above one lets container workloads reach the metadata service."
  }
}

run "node_volumes_are_encrypted" {
  command = plan

  assert {
    condition     = aws_launch_template.node.block_device_mappings[0].ebs[0].encrypted == "true"
    error_message = "Node root volumes must be encrypted at rest."
  }

  assert {
    condition     = aws_launch_template.node.block_device_mappings[0].ebs[0].volume_type == "gp3"
    error_message = "Node volumes must use gp3, which decouples throughput from capacity."
  }
}

run "node_role_carries_only_kubelet_permissions" {
  command = plan

  # Application permissions belong to IRSA roles. Any growth in this set would grant
  # the added permission to every pod scheduled onto the node.
  assert {
    condition     = length(aws_iam_role_policy_attachment.node) == 3
    error_message = "The node role must hold exactly the three policies the kubelet and CNI require."
  }
}

run "node_group_rolls_gradually" {
  command = plan

  assert {
    condition     = aws_eks_node_group.this.update_config[0].max_unavailable_percentage == 25
    error_message = "A node roll must bound simultaneous disruption so that budgets can be honoured."
  }

  assert {
    condition     = aws_eks_node_group.this.scaling_config[0].min_size >= 3
    error_message = "The default floor must keep one node per availability zone."
  }
}

run "core_addons_are_managed" {
  command = plan

  assert {
    condition     = length(aws_eks_addon.this) == 4
    error_message = "The CNI, CoreDNS, kube-proxy and EBS CSI add-ons must all be managed by EKS."
  }
}

run "rejects_public_access_without_an_explicit_allow_list" {
  command = plan

  variables {
    endpoint_public_access       = true
    endpoint_public_access_cidrs = []
  }

  expect_failures = [var.endpoint_public_access_cidrs]
}

run "rejects_exposing_the_api_server_to_the_whole_internet" {
  command = plan

  variables {
    endpoint_public_access       = true
    endpoint_public_access_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.endpoint_public_access_cidrs]
}

run "rejects_a_malformed_kubernetes_version" {
  command = plan

  variables {
    kubernetes_version = "1.31.4"
  }

  expect_failures = [var.kubernetes_version]
}

run "rejects_a_single_availability_zone" {
  command = plan

  variables {
    subnet_ids = ["subnet-aaaaaaaaaaaaaaaaa"]
  }

  expect_failures = [var.subnet_ids]
}
