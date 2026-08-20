# Composition tests for the production environment.
#
# These assert the properties that must differ from development. A production
# environment that quietly inherits a development trade-off is the failure this
# file exists to prevent.

mock_provider "aws" {}
mock_provider "tls" {}

# The mocked provider synthesises a value for every data source, and the generated
# strings are not valid JSON policy documents or ARN partitions. Overriding them
# leaves the composition itself under genuine test.
override_data {
  target = data.aws_iam_policy_document.workload
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

override_data {
  target = data.aws_iam_policy_document.artefacts_key
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

override_data {
  target = module.network.data.aws_iam_policy_document.flow_logs_key
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

override_data {
  target = module.network.data.aws_iam_policy_document.flow_logs_assume
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

override_data {
  target = module.network.data.aws_iam_policy_document.flow_logs_write
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

override_data {
  target = module.observability.data.aws_iam_policy_document.logs_key
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

override_data {
  target = module.eks.data.aws_iam_policy_document.cluster_assume
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

override_data {
  target = module.eks.data.aws_iam_policy_document.node_assume
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

override_data {
  target = module.eks.data.aws_iam_policy_document.secrets_key
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

override_data {
  target = module.eks.data.aws_iam_policy_document.logs_key
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

override_data {
  target = module.eks.data.aws_partition.current
  values = {
    partition = "aws"
  }
}

# Availability zones are supplied deterministically so that the address plan under
# test does not depend on what the API happens to return.
override_data {
  target = data.aws_availability_zones.available
  values = {
    names = ["eu-west-1c", "eu-west-1a", "eu-west-1b"]
  }
}

run "naming_is_derived_from_the_project_and_stage" {
  command = plan

  assert {
    condition     = local.environment == "prod"
    error_message = "The environment name is embedded in every resource name and in the state key."
  }

  assert {
    condition     = local.name == "demonstration-platform-prod"
    error_message = "Resource naming changed; cost allocation and log group paths depend on it."
  }
}

run "the_address_space_does_not_collide_with_development" {
  command = plan

  # The two environments must remain peerable without renumbering, so their ranges
  # are disjoint by construction rather than by convention.
  assert {
    condition     = join(",", module.network.private_subnet_cidrs) == "10.20.48.0/20,10.20.64.0/20,10.20.80.0/20"
    error_message = "The production address plan changed; it must stay disjoint from development."
  }

  assert {
    condition     = alltrue([for cidr in module.network.public_subnet_cidrs : startswith(cidr, "10.20.")])
    error_message = "Every subnet must fall inside the address space allocated to this environment."
  }
}

run "egress_survives_the_loss_of_an_availability_zone" {
  command = plan

  # The inverse of the development trade-off. One gateway per zone means losing a
  # zone removes capacity without severing egress for the zones that remain.
  assert {
    condition     = length(module.network.nat_gateway_ids) == 3
    error_message = "Production must provision one NAT gateway per availability zone."
  }
}

run "the_registry_is_encrypted_with_a_customer_managed_key" {
  command = plan

  assert {
    condition     = aws_kms_key.artefacts.enable_key_rotation
    error_message = "The artefact key must rotate automatically."
  }

  assert {
    condition     = aws_kms_key.artefacts.deletion_window_in_days == 30
    error_message = "The key must retain the maximum deletion window to survive an accidental destroy."
  }

  assert {
    condition     = aws_kms_alias.artefacts.name == "alias/demonstration-platform-prod-artefacts"
    error_message = "The key alias is referenced by the deployment pipeline."
  }
}

run "operators_are_handed_a_working_command" {
  command = plan

  assert {
    condition     = output.kubeconfig_command == "aws eks update-kubeconfig --region eu-west-1 --name demonstration-platform-prod"
    error_message = "The kubeconfig command is copied verbatim from the runbook and must be correct."
  }
}

run "the_api_endpoint_is_never_open_to_the_internet" {
  command = plan

  variables {
    operator_access_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.operator_access_cidrs]
}
