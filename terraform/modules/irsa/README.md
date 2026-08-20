# irsa

An IAM role assumable by exactly one Kubernetes service account through the
cluster's OIDC provider. See [ADR 0004](../../../docs/adr/0004-irsa-over-node-roles.md).

## Usage

```hcl
module "workload_irsa" {
  source = "../../modules/irsa"

  role_name            = "demonstration-platform-prod-workload"
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  namespace            = "demonstration"
  service_account_name = "demonstration-service"
  inline_policy_json   = data.aws_iam_policy_document.workload.json

  max_session_duration_seconds = 3600
}
```

Annotate the service account with the `role_arn` output:

```yaml
metadata:
  annotations:
    eks.amazonaws.com/role-arn: <role_arn>
```

## The security boundary

The trust policy carries two conditions, and they are the whole boundary:

- `<issuer>:sub` must equal `system:serviceaccount:<namespace>:<name>`. A
  `StringLike` comparison with a wildcard would let any service account in the
  cluster assume the role.
- `<issuer>:aud` must equal `sts.amazonaws.com`. Without it, a token minted for a
  different relying party would be accepted — the documented confused-deputy path.

The policy is written with `jsonencode` rather than assembled from a data source
precisely so that both conditions are literal and directly assertable in tests.

The module grants nothing by default. `permissions_boundary_arn` caps the effective
permissions regardless of any policy attached later.

## Tests

`terraform test` — nine runs, four of which exist solely to guard the trust policy
against widening, plus the session-duration bounds IAM enforces.
