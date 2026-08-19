# network

Three-tier VPC across the supplied availability zones: one public and one private
subnet per zone, NAT egress, flow logs, and the subnet discovery tags EKS and the
AWS Load Balancer Controller require.

Subnet addressing is derived from the VPC CIDR with `cidrsubnet`, so an environment
is re-homed by changing one variable with no risk of overlap.

## Usage

```hcl
module "network" {
  source = "../../modules/network"

  name               = "demonstration-platform-prod"
  vpc_cidr           = "10.20.0.0/16"
  availability_zones = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  cluster_name       = "demonstration-platform-prod"

  single_nat_gateway      = false
  flow_log_retention_days = 90
}
```

## Behaviour worth knowing

- The default security group is declared with no rules, so anything that falls back
  to it is isolated rather than implicitly permitted.
- Neither subnet tier auto-assigns public addresses; public addressing is granted
  explicitly to the resources that need it.
- Each private subnet has its own route table and egresses through the NAT gateway
  in its own zone, avoiding cross-zone transfer charges. Setting
  `single_nat_gateway` collapses the gateways but not the route tables.
- Flow logs are not optional: they are the only record of rejected traffic.

## Tests

`terraform test` — ten runs covering address derivation, zone redundancy, the
discovery tags, public-addressing defaults, flow log encryption, and the two
variable validations.
