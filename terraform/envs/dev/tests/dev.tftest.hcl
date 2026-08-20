# Composition tests for the development environment.
#
# The modules are unit-tested in their own directories. What is verified here is the
# composition: that the environment selects the intended trade-offs, that its address
# plan is the one documented, and that the values an operator is handed are correct.
#
# The provider is mocked, so no credentials are used and no API call is made.

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
    condition     = local.environment == "dev"
    error_message = "The environment name is embedded in every resource name and in the state key."
  }

  assert {
    condition     = local.name == "demonstration-platform-dev"
    error_message = "Resource naming changed; cost allocation and log group paths depend on it."
  }

  assert {
    condition     = local.cluster_name == "demonstration-platform-dev"
    error_message = "The cluster name is referenced by the subnet discovery tags."
  }
}

run "availability_zones_are_selected_in_a_stable_order" {
  command = plan

  # The API returns zones in an unspecified order. Sorting before slicing means a
  # change in that order cannot renumber the subnets and force their replacement.
  assert {
    condition     = join(",", local.availability_zones) == "eu-west-1a,eu-west-1b,eu-west-1c"
    error_message = "Zone selection must be sorted so that subnet numbering is stable."
  }

  assert {
    condition     = length(local.availability_zones) == 3
    error_message = "Three zones are required for a quorum-tolerant control plane."
  }
}

run "the_address_plan_is_the_documented_one" {
  command = plan

  assert {
    condition     = join(",", module.network.private_subnet_cidrs) == "10.10.48.0/20,10.10.64.0/20,10.10.80.0/20"
    error_message = "The private address plan changed; peering and firewall rules depend on it."
  }

  assert {
    condition     = alltrue([for cidr in module.network.public_subnet_cidrs : startswith(cidr, "10.10.")])
    error_message = "Every subnet must fall inside the address space allocated to this environment."
  }
}

run "cost_trade_offs_are_the_ones_recorded_for_development" {
  command = plan

  # Development accepts the loss of zonal redundancy in egress. Production does not,
  # and its own test asserts the opposite.
  assert {
    condition     = length(module.network.nat_gateway_ids) == 1
    error_message = "Development must collapse to a single NAT gateway."
  }
}

run "operators_are_handed_a_working_command" {
  command = plan

  assert {
    condition     = output.kubeconfig_command == "aws eks update-kubeconfig --region eu-west-1 --name demonstration-platform-dev"
    error_message = "The kubeconfig command is copied verbatim from the runbook and must be correct."
  }

  assert {
    condition     = output.region == "eu-west-1"
    error_message = "The region output feeds the deployment pipeline."
  }
}

run "the_api_endpoint_is_never_open_to_the_internet" {
  command = plan

  variables {
    operator_access_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.operator_access_cidrs]
}
