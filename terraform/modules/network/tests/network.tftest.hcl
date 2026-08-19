# Unit tests for the network module.
#
# The AWS provider is mocked, so no credentials are used and no API call is made.
# The assertions therefore cover what this module is actually responsible for:
# address derivation, redundancy behaviour, discovery tagging and the security
# defaults that must not regress.

mock_provider "aws" {}

# The mocked provider returns generated values for every data source, including the
# IAM policy documents, whose synthesised strings are not valid JSON and are rejected
# by the resources that consume them. Overriding those three data sources with real
# JSON keeps the rest of the module under genuine test.
override_data {
  target = data.aws_iam_policy_document.flow_logs_key
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

override_data {
  target = data.aws_iam_policy_document.flow_logs_assume
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

override_data {
  target = data.aws_iam_policy_document.flow_logs_write
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

variables {
  name               = "demo-platform"
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  cluster_name       = "demo-platform"
  tags               = { Environment = "test" }
}

run "subnet_cidrs_are_derived_without_overlap" {
  command = plan

  assert {
    condition     = length(setintersection(toset(local.public_subnet_cidrs), toset(local.private_subnet_cidrs))) == 0
    error_message = "Public and private subnet ranges must not overlap."
  }

  assert {
    condition     = local.public_subnet_cidrs == ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20"]
    error_message = "Public subnet derivation changed; downstream address plans depend on it."
  }

  assert {
    condition     = local.private_subnet_cidrs == ["10.0.48.0/20", "10.0.64.0/20", "10.0.80.0/20"]
    error_message = "Private subnet derivation changed; downstream address plans depend on it."
  }
}

run "one_subnet_pair_is_created_per_zone" {
  command = plan

  assert {
    condition     = length(aws_subnet.public) == 3 && length(aws_subnet.private) == 3
    error_message = "Each availability zone must receive exactly one public and one private subnet."
  }

  assert {
    condition     = length(aws_route_table.private) == 3
    error_message = "Each private subnet requires its own route table for zone-local NAT egress."
  }
}

run "production_defaults_are_zone_redundant" {
  command = plan

  assert {
    condition     = length(aws_nat_gateway.this) == 3
    error_message = "The default configuration must provision one NAT gateway per zone."
  }
}

run "cost_optimised_mode_collapses_to_a_single_nat_gateway" {
  command = plan

  variables {
    single_nat_gateway = true
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "Enabling single_nat_gateway must provision exactly one NAT gateway."
  }

  assert {
    condition     = length(aws_route_table.private) == 3
    error_message = "Collapsing NAT gateways must not collapse the private route tables."
  }
}

run "public_addressing_is_never_automatic" {
  command = plan

  assert {
    condition     = alltrue([for subnet in aws_subnet.public : subnet.map_public_ip_on_launch == false])
    error_message = "Public subnets must not auto-assign public IPv4 addresses."
  }

  assert {
    condition     = alltrue([for subnet in aws_subnet.private : subnet.map_public_ip_on_launch == false])
    error_message = "Private subnets must never auto-assign public IPv4 addresses."
  }
}

run "load_balancer_discovery_tags_are_present" {
  command = plan

  assert {
    condition     = alltrue([for subnet in aws_subnet.public : subnet.tags["kubernetes.io/role/elb"] == "1"])
    error_message = "Public subnets must carry the internet-facing load balancer discovery tag."
  }

  assert {
    condition     = alltrue([for subnet in aws_subnet.private : subnet.tags["kubernetes.io/role/internal-elb"] == "1"])
    error_message = "Private subnets must carry the internal load balancer discovery tag."
  }

  assert {
    condition     = alltrue([for subnet in aws_subnet.private : subnet.tags["kubernetes.io/cluster/demo-platform"] == "shared"])
    error_message = "Subnets must be tagged with the cluster they serve."
  }
}

run "flow_logs_are_encrypted_and_retained" {
  command = plan

  assert {
    condition     = aws_flow_log.this.traffic_type == "ALL"
    error_message = "Flow logs must capture accepted and rejected traffic."
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_logs.retention_in_days == 90
    error_message = "The flow log group must have an explicit retention period."
  }

  assert {
    condition     = aws_kms_key.flow_logs.enable_key_rotation
    error_message = "Automatic key rotation must be enabled on the flow log key."
  }
}

run "caller_supplied_tags_are_propagated" {
  command = plan

  assert {
    condition     = aws_vpc.this.tags["Environment"] == "test"
    error_message = "Tags supplied by the caller must reach every resource."
  }

  assert {
    condition     = aws_vpc.this.tags["ManagedBy"] == "terraform"
    error_message = "Provenance tagging must be applied automatically."
  }
}

run "rejects_an_address_space_too_small_to_subdivide" {
  command = plan

  variables {
    vpc_cidr = "10.0.0.0/24"
  }

  expect_failures = [var.vpc_cidr]
}

run "rejects_a_malformed_name" {
  command = plan

  variables {
    name = "Demo_Platform"
  }

  expect_failures = [var.name]
}
