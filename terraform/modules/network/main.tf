# Three-tier network topology for an EKS platform.
#
# Layout: one /16 VPC split into a public and a private subnet per availability
# zone. Nodes and pods run exclusively in the private subnets and reach the
# internet through NAT; only load balancers occupy the public subnets. This keeps
# the compute plane unreachable from the internet by construction rather than by
# security group rule alone.
#
# Addressing is derived from the VPC CIDR with cidrsubnet() rather than being
# enumerated by hand, so an environment can be re-homed by changing one variable
# without any risk of overlapping ranges.

locals {
  zone_count = length(var.availability_zones)

  # Public subnets occupy the first block of the address space and private subnets
  # the second, which keeps the two tiers summarisable as contiguous ranges.
  public_subnet_cidrs  = [for index in range(local.zone_count) : cidrsubnet(var.vpc_cidr, 4, index)]
  private_subnet_cidrs = [for index in range(local.zone_count) : cidrsubnet(var.vpc_cidr, 4, index + local.zone_count)]

  nat_gateway_count = var.single_nat_gateway ? 1 : local.zone_count

  tags = merge(var.tags, {
    "Name"      = var.name
    "Module"    = "network"
    "ManagedBy" = "terraform"
  })
}

resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr

  # Required by EKS: the kubelet resolves the private DNS name of its instance.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { "Name" = "${var.name}-vpc" })
}

# The default security group permits unrestricted intra-group traffic. Declaring it
# with no rules empties it, so any resource that inadvertently falls back to the
# default is isolated rather than silently permitted.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { "Name" = "${var.name}-default-deny" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { "Name" = "${var.name}-igw" })
}

resource "aws_subnet" "public" {
  count = local.zone_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  # Public addressing is granted explicitly to the resources that need it, never
  # automatically to everything launched in the subnet.
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    "Name" = "${var.name}-public-${var.availability_zones[count.index]}"
    "Tier" = "public"
    # Discovery tags consumed by the AWS Load Balancer Controller when it places
    # internet-facing load balancers.
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

resource "aws_subnet" "private" {
  count = local.zone_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    "Name" = "${var.name}-private-${var.availability_zones[count.index]}"
    "Tier" = "private"
    # Discovery tags for internal load balancers and for the EKS control plane's
    # elastic network interfaces.
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"

  tags = merge(local.tags, { "Name" = "${var.name}-nat-${count.index}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.tags, { "Name" = "${var.name}-nat-${count.index}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { "Name" = "${var.name}-public" })
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = local.zone_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# One route table per private subnet, so that each zone can egress through the NAT
# gateway in its own zone. A shared table would send cross-zone traffic through a
# single gateway, adding both latency and inter-zone data transfer charges.
resource "aws_route_table" "private" {
  count = local.zone_count

  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { "Name" = "${var.name}-private-${var.availability_zones[count.index]}" })
}

resource "aws_route" "private_default" {
  count = local.zone_count

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.single_nat_gateway ? 0 : count.index].id
}

resource "aws_route_table_association" "private" {
  count = local.zone_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ---------------------------------------------------------------------------
# Flow logs
# ---------------------------------------------------------------------------
# Flow logs are the only record of rejected traffic at the network layer and are a
# prerequisite for incident investigation, so they are not optional in this module.

resource "aws_cloudwatch_log_group" "flow_logs" {
  # checkov:skip=CKV_AWS_338:Retention is a per-environment decision surfaced as a
  # variable. Ninety days covers the investigation window agreed for flow logs; a
  # full year of packet metadata is retained only where a compliance regime requires
  # it, and the value can be raised per environment without a code change.
  name              = "/aws/vpc/${var.name}/flow-logs"
  retention_in_days = var.flow_log_retention_days
  kms_key_id        = aws_kms_key.flow_logs.arn

  tags = local.tags
}

resource "aws_kms_key" "flow_logs" {
  description             = "Encrypts the VPC flow log group for ${var.name}."
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = data.aws_iam_policy_document.flow_logs_key.json

  tags = local.tags
}

resource "aws_kms_alias" "flow_logs" {
  name          = "alias/${var.name}-vpc-flow-logs"
  target_key_id = aws_kms_key.flow_logs.key_id
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_iam_policy_document" "flow_logs_key" {
  # checkov:skip=CKV_AWS_356:A key policy is attached to one key and evaluated only for
  # that key, so "*" denotes the key itself. AWS rejects any other resource value.
  # checkov:skip=CKV_AWS_109:Administrative rights for the account root are mandatory;
  # omitting them renders the key permanently unmanageable.
  # checkov:skip=CKV_AWS_111:As above. Service access is constrained by principal and
  # by the encryption context condition below.
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
      values   = ["arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:*"]
    }
  }
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${var.name}-vpc-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json

  tags = local.tags
}

data "aws_iam_policy_document" "flow_logs_write" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]

    resources = ["${aws_cloudwatch_log_group.flow_logs.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "${var.name}-vpc-flow-logs"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs_write.json
}

resource "aws_flow_log" "this" {
  vpc_id                   = aws_vpc.this.id
  traffic_type             = "ALL"
  iam_role_arn             = aws_iam_role.flow_logs.arn
  log_destination          = aws_cloudwatch_log_group.flow_logs.arn
  log_destination_type     = "cloud-watch-logs"
  max_aggregation_interval = 60

  tags = merge(local.tags, { "Name" = "${var.name}-flow-logs" })
}
