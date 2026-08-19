# 3. Mocked `terraform test` rather than LocalStack

- Status: Accepted
- Date: 2026-08-19

## Context

The Terraform configuration must be verified on every push, in a repository that
has no AWS account and deploys nothing. `terraform validate` proves only that the
configuration parses and type-checks; it cannot detect that a subnet calculation is
wrong, that encryption was disabled, or that an IAM trust policy was widened.

Three options were considered: `terraform plan` against a real account, LocalStack
emulating the AWS APIs, and the native testing framework with `mock_provider`.

## Decision

Use `terraform test` with `mock_provider`, and omit `plan` from the pipeline.

## Rationale

- A plan requires credentials, a state backend and an account. It would prove that
  the configuration matches an account this repository deliberately does not have.
- LocalStack does not emulate EKS, IAM OIDC providers or KMS grants in its free
  tier, which is precisely the surface that carries the risk here. It would add a
  container, a start-up cost on every run, and a second definition of AWS behaviour
  that can drift from the real one.
- `mock_provider` needs no credentials, no network and no state. Test execution is
  a few seconds per module. Crucially the assertions target the module's own logic:
  address derivation, redundancy, tagging, and the security defaults.
- `expect_failures` makes variable validation testable, so the guard rails
  themselves are covered — for example, that public API access cannot be enabled
  without an explicit allow-list, and that `0.0.0.0/0` is rejected outright.

## Consequences

**Accepted.** Nothing verifies that AWS would accept the configuration; a service
quota, an unsupported argument combination or a regional gap would surface only on
a real apply. `tflint` with the AWS ruleset narrows this gap but does not close it.
Mocked values are synthesised, so assertions must target inputs and derived values
rather than computed attributes — the reason three IAM policy documents are
overridden explicitly in the tests.

**Gained.** Forty-three assertions covering the parts of the configuration that
carry real risk, running in seconds, on every push, at no cost, with no credentials
in existence anywhere.

Where a real plan is wanted before an apply, it belongs in a separate pipeline that
federates into an account through OIDC — the shape of which is already present, and
dormant, in `ci.yml`.
