# Local development

## Prerequisites

| Tool | Minimum version | Used for |
| --- | --- | --- |
| Python | 3.12 | The application and its tests |
| Docker | 24 | Building and running the image, and hosting the local cluster |
| Terraform | 1.10 | `validate` and `test`; 1.10 introduces native S3 state locking |
| kubectl | 1.30 | Applying manifests; supplies `kubectl kustomize` |
| kind | 0.30 | The local Kubernetes cluster |
| kubeconform | 0.7 | Validating manifests against the upstream schemas |
| Make | 4 | The task entry points |
| shellcheck | 0.9 | Linting the shell scripts; run through its published image |

Kustomize is not required separately: `kubectl kustomize` renders the overlays.

```bash
# kubectl
curl -fsSLO "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -m 0755 kubectl ~/.local/bin/kubectl

# kind
curl -fsSLo kind https://kind.sigs.k8s.io/dl/v0.30.0/kind-linux-amd64
install -m 0755 kind ~/.local/bin/kind

# kubeconform
curl -fsSL https://github.com/yannh/kubeconform/releases/download/v0.7.0/kubeconform-linux-amd64.tar.gz \
  | tar -xz kubeconform && install -m 0755 kubeconform ~/.local/bin/kubeconform
```

Verify downloaded binaries against the checksums published alongside each release
before installing them.

## The loop

```bash
make install    # editable install with the development extras
make lint       # ruff, mypy, terraform, kubeconform, manifest policy, shellcheck
make test       # pytest at a 100 % gate, and terraform test for modules and envs
make build      # build the image and run it read-only and unprivileged
make scan       # Trivy against the exported image
make k8s-up     # create the cluster, load the image, apply the dev overlay
make verify     # await the rollout and assert the workload's contracts
make k8s-down   # remove the cluster
```

Two checks are worth knowing about individually:

- `scripts/manifest-policy.py` renders both overlays and asserts the invariants that
  schema validation cannot see. It is the only verification the production overlay
  receives, since no local cluster can provision a load balancer or an IAM role.
- `make scan-terraform` runs Checkov. Deviations from its default policy are recorded
  as `checkov:skip` comments at the point the decision is made, never in a central
  ignore list.

`make all` runs the sequence end to end. `make help` lists every target.

Install the pre-commit hooks to run the same checks before each commit:

```bash
pre-commit install
```

## Reaching the running service

```bash
kubectl -n demonstration port-forward service/demonstration-service 8080:80
curl -s localhost:8080/ | python3 -m json.tool
curl -s localhost:8080/metrics | head
```

## Working on the Terraform

Each module is testable on its own. No credentials are required, because the tests
mock the provider:

```bash
cd terraform/modules/network
terraform init -backend=false
terraform test
```

`terraform plan` is not part of the workflow. It requires credentials and a state
backend, and this repository has neither by design — see
[ADR 0003](adr/0003-terraform-test-over-localstack.md).

## Notes

- The application listens on port 8000; the Service publishes port 80.
- The container runs as UID 10001 on a read-only root filesystem. Anything that
  needs to write must be given an explicit volume, as `/tmp` is.
- kind's default CNI does not enforce NetworkPolicy. The policies are admitted and
  schema-checked locally; enforcement is exercised on EKS.
- The HorizontalPodAutoscaler has no metrics source in kind and will report unknown
  metrics. It is applied to prove it is valid and admitted, not to scale anything.
