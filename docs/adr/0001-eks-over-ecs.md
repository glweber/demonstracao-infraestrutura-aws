# 1. EKS rather than ECS

- Status: Accepted
- Date: 2026-08-19

## Context

The platform must orchestrate containers on AWS. Both Amazon ECS and Amazon EKS are
managed services that would satisfy the functional requirement, and ECS is
materially simpler: no control plane charge, no version upgrades, and an IAM model
the team already understands.

## Decision

Use Amazon EKS.

## Rationale

- Kubernetes is a portable interface. The manifests in `k8s/` run unmodified on any
  conformant cluster, which is what allows continuous integration to exercise them
  on a local cluster with no AWS account. An ECS task definition has no equivalent
  and could only be checked statically.
- The surrounding ecosystem — Pod Security Admission, NetworkPolicy,
  PodDisruptionBudget, HorizontalPodAutoscaler, topology spread — is a body of
  operational primitives with no ECS counterpart. Several of the controls this
  platform relies on would have to be rebuilt or abandoned.
- The stated requirement names Kubernetes explicitly.

## Consequences

**Accepted.** A control plane charge per cluster per hour. Responsibility for minor
version upgrades roughly three times a year. A larger surface to secure, which is
why secret encryption, audit logging and IMDSv2 hardening are configured in the
module rather than left to the operator.

**Gained.** Manifests that are verifiable off AWS entirely, which is what makes the
continuous integration in this repository possible.
