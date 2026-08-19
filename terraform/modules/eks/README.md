# eks

Managed control plane, one managed node group and the core add-ons, plus the IAM
OIDC provider that underpins IRSA.

## Usage

```hcl
module "eks" {
  source = "../../modules/eks"

  cluster_name       = "demonstration-platform-prod"
  kubernetes_version = "1.31"
  subnet_ids         = module.network.private_subnet_ids

  endpoint_public_access       = true
  endpoint_public_access_cidrs = ["203.0.113.0/24"]

  node_instance_types = ["m6i.large", "m6a.large"]
  node_capacity_type  = "ON_DEMAND"
  node_min_size       = 3
  node_max_size       = 9
}
```

## Decisions encoded here

Four properties are difficult to retrofit once a cluster carries workloads, so they
are configured rather than left to the operator:

1. Kubernetes secrets are envelope-encrypted with a rotating customer-managed KMS
   key. Without an encryption provider, secrets are only base64-encoded in etcd.
2. All five control plane log types are shipped, the audit log above all — it cannot
   be recovered retrospectively.
3. Nodes join through a launch template that requires IMDSv2 with a one-hop limit,
   which is what stops a container reaching the metadata service and harvesting the
   node role's credentials.
4. Authentication uses access entries (`authentication_mode = "API"`), not the
   `aws-auth` ConfigMap, so cluster access is declared in code and audited by
   CloudTrail.

Public API access requires an explicit allow-list, and `0.0.0.0/0` is rejected by
variable validation.

## Tests

`terraform test` — thirteen runs covering the four decisions above, node volume
encryption, node role scope, roll behaviour, add-on management, and four variable
validations.
