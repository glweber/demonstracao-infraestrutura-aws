# 4. IRSA rather than node instance roles

- Status: Accepted
- Date: 2026-08-19

## Context

The workload needs AWS permissions. Three mechanisms exist: an access key held in a
Kubernetes secret, permissions attached to the node instance profile, or IAM Roles
for Service Accounts.

## Decision

Use IRSA. The node role carries only what the kubelet and CNI require.

## Rationale

- An access key is a long-lived credential that must be stored, distributed and
  rotated, and it remains valid wherever it is copied. There is no reason to create
  one on a platform that offers federation.
- Permissions on the node instance profile are inherited by every pod scheduled
  onto that node, including pods from other teams and future workloads nobody has
  written yet. The grant is invisible from the workload's own manifest.
- IRSA binds a role to a single service account in a single namespace, through the
  `sub` condition in the trust policy. The credential is issued by STS, is bounded by
  the role's session ceiling of one hour, and is renewed from a projected token that
  the kubelet rotates well before it expires.
- The permission is visible where it is used: an annotation on the service account,
  next to the workload that relies on it.

## Consequences

**Accepted.** Every workload needing AWS access requires its own role and trust
policy, so the number of roles grows with the number of workloads. The cluster must
have an OIDC provider registered, which the `eks` module creates.

**Gained.** No long-lived credential exists anywhere in the system. A compromised
pod obtains only its own permissions, bounded by the role's one-hour session ceiling,
and an explicit deny on the role revokes even that immediately.

**Guarded.** Two properties in the trust policy are the entire boundary, so both are
asserted in `terraform/modules/irsa/tests/`: the subject must be an exact match
rather than a wildcard, and the audience must be `sts.amazonaws.com`. Omitting the
audience check is the documented confused-deputy path.
