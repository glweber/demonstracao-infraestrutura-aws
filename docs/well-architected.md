# AWS Well-Architected mapping

Each pillar below lists the controls this repository actually implements, the file
that implements them, and — where a pillar is only partly addressed — what is
missing and why.

## Operational excellence

| Control | Where |
| --- | --- |
| The entire platform is defined as code and reviewed through pull requests | `terraform/`, `k8s/` |
| Identical local and CI entry points, so a failure reproduces with the same command | `Makefile` |
| Structured JSON logs to stdout, collected by the node agent | `app/src/service/logging_setup.py` |
| Every resource carries `Environment`, `Project`, `Owner`, `ManagedBy` through provider default tags | `terraform/envs/*/providers.tf` |
| Deploy, rollback and triage procedures written down | `docs/runbook.md` |
| Decisions recorded with their context and consequences | `docs/adr/` |

## Security

| Control | Where |
| --- | --- |
| Kubernetes secrets encrypted with a rotating customer-managed KMS key | `terraform/modules/eks/main.tf` |
| All five control plane log types shipped, including the audit log | `terraform/modules/eks/main.tf` |
| IMDSv2 mandatory with a single-hop limit, so containers cannot reach node credentials | `terraform/modules/eks/main.tf` |
| Workload permissions through IRSA, scoped to one service account, never to the node | `terraform/modules/irsa/main.tf` |
| Containers run as UID 10001, read-only root filesystem, all capabilities dropped | `k8s/base/deployment.yaml` |
| `restricted` Pod Security Admission enforced at the namespace | `k8s/base/namespace.yaml` |
| Default-deny NetworkPolicy; only port 8000 in and DNS out | `k8s/base/networkpolicy.yaml` |
| Immutable image tags and scan-on-push | `terraform/modules/ecr/main.tf` |
| VPC flow logs, encrypted and retained | `terraform/modules/network/main.tf` |
| The default security group emptied, so nothing inherits an implicit allow | `terraform/modules/network/main.tf` |
| No long-lived credentials: OIDC federation with a 15-minute session | `.github/workflows/ci.yml` |
| Every third-party action pinned to a commit SHA | `.github/workflows/` |
| Secret scanning, image scanning and configuration scanning gate the build | `.pre-commit-config.yaml`, `.github/workflows/` |

## Reliability

| Control | Where |
| --- | --- |
| Three availability zones, each with its own NAT gateway and route table | `terraform/modules/network/main.tf` |
| Zonal spread enforced in production (`DoNotSchedule`) | `k8s/overlays/prod/patch-scale.yaml` |
| PodDisruptionBudget bounding voluntary disruption during drains | `k8s/base/poddisruptionbudget.yaml` |
| Rolling updates that surge before terminating (`maxUnavailable: 0`) | `k8s/base/deployment.yaml` |
| Distinct liveness, readiness and startup probes | `app/src/service/main.py`, `k8s/base/deployment.yaml` |
| Graceful draining: readiness withdrawn, `preStop` pause, 45-second grace period | `k8s/base/deployment.yaml` |
| Node group rolls at most 25 % at a time | `terraform/modules/eks/main.tf` |
| Autoscaling that rises quickly and retreats slowly | `k8s/base/horizontalpodautoscaler.yaml` |
| Alarm fails towards alerting: missing data is treated as breaching | `terraform/modules/observability/main.tf` |

**Not addressed.** No backup or restore procedure, because the workload is
stateless and holds no data store. No multi-region recovery, because no recovery
objective has been stated — see `docs/architecture.md`.

## Performance efficiency

| Control | Where |
| --- | --- |
| gp3 volumes, which decouple throughput from capacity | `terraform/modules/eks/main.tf` |
| CPU requested but not limited, so tail latency is not throttled away; memory limited because it is incompressible | `k8s/base/deployment.yaml` |
| Load balancer targets pod addresses directly, removing the node-port hop | `k8s/overlays/prod/ingress.yaml` |
| Request latency histogram exposed for scraping | `app/src/service/main.py` |
| Metric labels use the route template, bounding cardinality | `app/src/service/main.py` |
| Horizontal autoscaling on CPU utilisation | `k8s/base/horizontalpodautoscaler.yaml` |

## Cost optimisation

| Control | Where |
| --- | --- |
| Development collapses to a single NAT gateway; production keeps one per zone | `terraform/envs/dev/main.tf` |
| Spot capacity in development, on-demand in production | `terraform/envs/*/main.tf` |
| Explicit log retention everywhere — the default of never expiring accrues cost indefinitely | `terraform/modules/*` |
| Registry lifecycle policy expiring untagged layers and bounding release history | `terraform/modules/ecr/main.tf` |
| Cost allocation tags applied by the provider, so no resource can escape them | `terraform/envs/*/providers.tf` |
| Zone-local NAT egress, avoiding cross-zone data transfer charges | `terraform/modules/network/main.tf` |

## Sustainability

| Control | Where |
| --- | --- |
| Multi-stage build; the runtime layer carries no toolchain or package cache | `docker/Dockerfile` |
| Autoscaling floors sized to demand rather than to peak | `k8s/base/horizontalpodautoscaler.yaml` |
| Spot capacity in development, using otherwise idle fleet | `terraform/envs/dev/main.tf` |
| Retention limits on logs and images, so storage does not grow without bound | `terraform/modules/*` |
