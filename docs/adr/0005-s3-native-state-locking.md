# 5. Native S3 state locking rather than a DynamoDB table

- Status: Accepted
- Date: 2026-08-19

## Context

Remote Terraform state requires a lock so that two concurrent applies cannot
interleave and corrupt it. The long-standing pattern pairs an S3 bucket with a
DynamoDB table specified through `dynamodb_table`.

Terraform 1.10 added `use_lockfile`, which implements the lock as a conditional
write of a `.tflock` object next to the state file, using the same S3 conditional
write primitive that underpins the DynamoDB approach.

## Decision

Use `use_lockfile = true` on the S3 backend. Do not create a DynamoDB table.
Require Terraform 1.10 or later.

## Rationale

- One less resource to bootstrap, pay for, monitor and grant permissions to. The
  DynamoDB table was always a workaround for S3's historical lack of conditional
  writes, which it has now had for some time.
- The lock lives beside the state it protects, so permissions are expressed once
  against the bucket rather than split across two services.
- HashiCorp has deprecated `dynamodb_table` in favour of this mechanism, so the
  table is the option that now carries a migration ahead of it.

## Consequences

**Accepted.** Terraform 1.10 or later is required, which is stated in
`required_version` across every module and environment. An existing state using a
DynamoDB lock needs a documented migration, though none exists here.

**Gained.** The bootstrap reduces to a single bucket with versioning enabled,
public access blocked and default encryption applied. Nothing else is needed before
the first `init`.

**Note.** The backend in this repository is intentionally left partially configured:
the bucket name is supplied at initialisation rather than committed, so the same
configuration serves any account. Continuous integration runs
`terraform init -backend=false`, so no state is read and no credentials exist.
