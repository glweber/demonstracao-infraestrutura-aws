# Terraform

Five reusable modules and two environments that compose them. Nothing here is ever
applied: the configuration is verified statically and by unit tests against a mocked
provider, so no credentials exist and no state is held.

## Layout

```
modules/
  network/        VPC across three zones, NAT egress, flow logs, subnet discovery tags
  eks/            Control plane, node group, add-ons, OIDC provider for IRSA
  ecr/            Registry with immutable tags, scan on push, lifecycle policy
  irsa/           One IAM role assumable by exactly one Kubernetes service account
  observability/  Log group, error-rate metric filter, alarm and topic
envs/
  dev/            Cost-optimised composition
  prod/           Availability-optimised composition
```

Each module follows the standard structure — `main.tf`, `variables.tf`,
`outputs.tf`, `versions.tf`, `README.md`, `tests/` — with every variable typed and
described, every output described, and validation blocks encoding the constraints
that would otherwise fail at apply time.

## Verification

```bash
make lint-terraform         # fmt -check and validate across every directory
make lint-terraform-rules   # tflint with the AWS ruleset
make scan-terraform         # Checkov
make test-terraform         # terraform test for both modules and environments
```

Fifty-six test runs in total. The environments are root modules with tests of their
own, because a module can be individually correct while an environment quietly
inherits the wrong trade-off.

`terraform plan` is deliberately absent from the pipeline: it requires credentials
and a state backend, and would prove only that the configuration matches an account
this repository does not have. See
[ADR 0003](../docs/adr/0003-terraform-test-over-localstack.md).

## Testing against a mocked provider

`mock_provider "aws" {}` synthesises a value for every attribute and data source.
Two consequences shape how the tests are written:

- Generated strings are not valid JSON policy documents or ARN partitions, so those
  data sources are supplied explicitly with `override_data`. Everything else stays
  under genuine test.
- Computed attributes are unknown while planning, so assertions target inputs,
  derived locals and known configuration rather than values the API would return.
  Where a resource's identifier is unknown, the assertion targets its alias or its
  count instead.

## Deviations from the Checkov default policy

Recorded as `checkov:skip` comments at the point the decision is made, never in a
central ignore list, so the justification is read by whoever next edits the line.
The recurring ones:

| Check | Why it is not applicable |
| --- | --- |
| `CKV_AWS_356`, `CKV_AWS_109`, `CKV_AWS_111` | A KMS key policy is attached to one key and evaluated only for that key, so `"*"` denotes the key itself; AWS rejects any other value. Account root administration is mandatory, or the key becomes unmanageable |
| `CKV_AWS_338` | Log retention is a per-environment decision surfaced as a variable. Production sets a year; development accepts thirty days deliberately |
| `CKV_AWS_39` | The API endpoint stays publicly reachable, but variable validation forbids an empty allow-list and rejects `0.0.0.0/0` outright |

## State

The backend is intentionally partially configured. The bucket name is supplied at
initialisation rather than committed, so the same configuration serves any account:

```bash
terraform init \
  -backend-config="bucket=<state-bucket>" \
  -backend-config="region=<region>"
```

Locking uses `use_lockfile`, a conditional write of a `.tflock` object beside the
state, which supersedes the DynamoDB table earlier versions required. See
[ADR 0005](../docs/adr/0005-s3-native-state-locking.md).

The bucket is created outside this configuration — a configuration cannot store its
own state in a bucket it has yet to create — and must have versioning enabled,
public access blocked and default encryption applied.

Continuous integration runs `terraform init -backend=false`, so no state is read.
