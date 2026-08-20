# Kubernetes

A Kustomize base carrying every production control, and two overlays that diverge
only where an environment genuinely differs.

```
base/                  namespace, service account, deployment, service,
                       disruption budget, autoscaler, network policies
overlays/dev/          local image, one replica, no ingress
overlays/prod/         registry image, ALB ingress, IRSA annotation, tighter sizing
kind-cluster.yaml      the local cluster definition used by CI and by developers
```

## Controls in the base

Applied to every environment, so an overlay must actively opt out rather than
forget to opt in:

- `restricted` Pod Security Admission enforced at the namespace, with warning and
  auditing set one level ahead so a future tightening is visible before it rejects
  anything.
- Non-root UID 10001, read-only root filesystem, all capabilities dropped,
  `RuntimeDefault` seccomp, no privilege escalation.
- No service account token mounted. IRSA is unaffected: the identity webhook
  projects a separate, audience-scoped token when the role annotation is present.
- Distinct startup, liveness and readiness probes.
- Graceful draining: readiness withdrawn on shutdown, a `preStop` pause, and a
  45-second grace period, because endpoint removal is asynchronous with SIGTERM.
- CPU requested but not limited — a limit only throttles tail latency once the
  guarantee is met. Memory is limited because it is incompressible.
- Rolling updates that surge before terminating, so capacity never dips.
- Default-deny NetworkPolicy selecting every pod, including workloads added later.

## Why the overlays differ

The development overlay targets a local cluster: one replica, an image side-loaded
from the local daemon, and no Ingress, because an Application Load Balancer has no
counterpart in kind and a resource that cannot reconcile is worse than one that is
absent. Port-forwarding covers the same need.

Production adds the ALB Ingress, the IRSA annotation, three replicas and required
zonal spread.

## How each overlay is verified

| | Development | Production |
| --- | --- | --- |
| Rendered by kustomize | yes | yes |
| Schema validated by kubeconform | yes | yes |
| Policy assertions | yes | yes |
| Applied to a real cluster | yes, on every push | no — see below |
| Workload exercised over the network | yes | no |

Production cannot be applied here: no cluster in this repository can provision a
load balancer or an IAM role. Schema validation alone would accept a manifest that
runs as root, pulls a mutable tag or omits a probe, so
`scripts/manifest-policy.py` renders both overlays and asserts the invariants
instead — fifty-nine checks covering the security context, image immutability,
probe separation, resource declarations, zonal spread, the IRSA annotation and the
load balancer configuration.

That checker was itself verified by injecting five regressions — a writable root
filesystem, spread degraded to a preference, a `latest` tag, a health check pointed
at liveness, and a removed IRSA annotation — and confirming each is caught.

## Known limitation

kind's default CNI does not implement NetworkPolicy. Locally and in CI the policies
are proven to be schema-valid and admitted, not enforced; enforcement is exercised
on EKS with the VPC CNI.

The HorizontalPodAutoscaler likewise has no metrics source in kind and reports
unknown metrics there. It is applied to prove it is valid and admitted.

## Running it

```bash
make build     # the image the dev overlay expects
make k8s-up    # create the cluster, side-load the image, apply the dev overlay
make verify    # await rollout, then assert the workload's contracts
make k8s-down
```
