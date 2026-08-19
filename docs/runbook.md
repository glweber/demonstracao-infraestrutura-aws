# Runbook

Operational procedures for the platform. Every command below assumes `kubectl` is
pointed at the target cluster and that `NAMESPACE=demonstration`.

## Deploy a release

1. Tag the commit: `git tag v1.2.3 && git push origin v1.2.3`.
2. CI builds, scans and — once an AWS role is configured — pushes the image to ECR.
3. Update the tag in `k8s/overlays/prod/kustomization.yaml` and merge.
4. Apply and await the rollout:

```bash
kubectl apply -k k8s/overlays/prod
kubectl -n demonstration rollout status deployment/demonstration-service --timeout=300s
```

The rollout surges before terminating (`maxUnavailable: 0`), so capacity never dips
below the declared replica count.

## Roll back

```bash
kubectl -n demonstration rollout undo deployment/demonstration-service
kubectl -n demonstration rollout status deployment/demonstration-service
```

Five revisions are retained. If the bad revision has already aged out, re-apply the
previous image tag: ECR retains the last fifty release images, and tags are
immutable, so a given tag always resolves to the same content.

## The service is unavailable

```bash
kubectl -n demonstration get pods -o wide
kubectl -n demonstration describe pod <pod>
kubectl -n demonstration logs deployment/demonstration-service --tail=200
kubectl get events -n demonstration --sort-by=.lastTimestamp | tail -30
```

| Symptom | Likely cause | Action |
| --- | --- | --- |
| `CrashLoopBackOff` immediately after start | Invalid configuration; `load_settings` raises and the process exits | Read the first log line; correct the environment variable in the overlay |
| `CreateContainerConfigError` | Missing referenced secret or config map | `kubectl describe pod` names the missing object |
| Pods `Running` but not `Ready` | `/readyz` returning 503 | Check the readiness probe events; the startup probe allows 60 seconds before liveness applies |
| `Pending` with no node | Insufficient capacity, or the zonal spread cannot be satisfied | `kubectl describe pod` reports the failed predicate; check node group scaling |
| `ImagePullBackOff` | Tag absent, or the node role cannot read the repository | Confirm the tag exists in ECR and that the node role retains `AmazonEC2ContainerRegistryReadOnly` |
| 503 from the load balancer, pods healthy | Targets not registered | Check the load balancer controller logs and the subnet discovery tags |

## The error rate alarm has fired

The alarm fires when more than the configured number of `ERROR` or `CRITICAL` log
records occur in two consecutive five-minute periods.

```bash
aws logs filter-log-events \
  --log-group-name /aws/containerinsights/<cluster>/application \
  --filter-pattern '{ $.level = "ERROR" }' \
  --start-time $(( ($(date +%s) - 1800) * 1000 ))
```

`treat_missing_data` is `breaching`: the alarm also fires when telemetry stops
arriving. Confirm the workload is still emitting logs before assuming an
application fault.

## A node must be drained

```bash
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
```

The PodDisruptionBudget allows one replica to be unavailable at a time, so the
drain blocks rather than breaching availability. A drain that hangs indefinitely
means the replacement pod cannot schedule — check capacity and the spread
constraints before overriding the budget.

## Rotate the workload's AWS permissions

Edit the policy document in the environment's `main.tf` and apply. Roles are bound
to a single service account through the OIDC subject condition, so a change affects
exactly one workload. No credential is distributed, and nothing needs restarting:
the SDK re-reads the projected token, which is rotated by the kubelet.

## Emergency: revoke a compromised workload identity

```bash
aws iam put-role-policy --role-name <role> --policy-name emergency-deny \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Deny","Action":"*","Resource":"*"}]}'
```

An explicit deny overrides every allow immediately. Sessions already issued remain
valid for at most fifteen minutes in production, which is the reason the session
duration is set to the floor.
