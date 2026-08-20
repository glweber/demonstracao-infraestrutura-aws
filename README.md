# AWS infrastructure demonstration

[![ci](https://github.com/glweber/demonstracao-infraestrutura-aws/actions/workflows/ci.yml/badge.svg)](https://github.com/glweber/demonstracao-infraestrutura-aws/actions/workflows/ci.yml)
[![terraform](https://github.com/glweber/demonstracao-infraestrutura-aws/actions/workflows/terraform.yml/badge.svg)](https://github.com/glweber/demonstracao-infraestrutura-aws/actions/workflows/terraform.yml)
[![kubernetes](https://github.com/glweber/demonstracao-infraestrutura-aws/actions/workflows/kubernetes.yml/badge.svg)](https://github.com/glweber/demonstracao-infraestrutura-aws/actions/workflows/kubernetes.yml)
[![licence](https://img.shields.io/badge/licence-Apache--2.0-blue)](LICENSE)

A reference implementation of a container platform on AWS: a three-tier VPC, an
EKS cluster, a container registry, workload identity, observability, the Kubernetes
manifests for a workload, and the pipelines that verify all of it.

## Nothing is deployed, and nothing is published

This repository provisions no live infrastructure. It holds no credentials, no
account identifiers and no state, and it pushes no image to any registry. Every
AWS identifier in the configuration is a documented placeholder, and every address
range is drawn from the ranges RFC 5737 reserves for documentation.

That constraint shapes the whole design. A repository of infrastructure code that
is never applied proves very little on its own — it is indistinguishable from
configuration copied from a tutorial. So the verification is inverted: **everything
here is proven by something that actually executes**, free of charge, without an
AWS account, on every push.

| Requirement | Artefact | How it is verified |
| --- | --- | --- |
| Cloud infrastructure on AWS | `terraform/` — VPC, EKS, ECR, IRSA, KMS, CloudWatch | `validate`, `tflint`, `checkov`, and 43 unit tests |
| Container orchestration | `k8s/` — base and two overlays | applied to a real cluster in CI, rollout awaited, workload exercised |
| Containers | `docker/Dockerfile` | built, run unprivileged and read-only, scanned with Trivy |
| Infrastructure as code | `terraform/modules/`, `terraform/envs/` | `terraform test` against a mocked provider — no credentials |
| CI/CD | `.github/workflows/` | the three pipelines that run everything above |

The path to AWS is written out in full and left dormant: the `publish` job in
`ci.yml` assumes a role through OIDC federation and pushes to Amazon ECR, guarded
by `if: vars.AWS_ROLE_ARN != ''`. That variable is never set. The job is complete
and reviewable; it simply never runs. Fully wired, never fired.

## Verification without an AWS account

```bash
make lint      # ruff, mypy, terraform fmt and validate, kustomize, kubeconform
make test      # pytest with a coverage gate, and terraform test against mocks
make build     # build the image, then run it read-only and unprivileged
make k8s-up    # create a local cluster, load the image, apply the dev overlay
make verify    # await the rollout and assert the workload's contracts
make k8s-down
```

`make all` runs the sequence end to end. Prerequisites are listed in
[docs/local-development.md](docs/local-development.md).

## Layout

```
app/         FastAPI workload: distinct liveness and readiness, metrics, JSON logs
docker/      Multi-stage build, digest-pinned base, non-root, read-only rootfs
terraform/   Five modules, two environments, unit tests beside each module
k8s/         Kustomize base and dev/prod overlays
.github/     Three pipelines; every action pinned to a commit SHA
docs/        Architecture, Well-Architected mapping, runbook, ADRs
scripts/     Cluster lifecycle and the smoke tests used by CI
```

## Design decisions

The reasoning behind the choices that a reader would otherwise have to reverse
engineer is recorded as architecture decision records:

| ADR | Decision |
| --- | --- |
| [0001](docs/adr/0001-eks-over-ecs.md) | EKS rather than ECS |
| [0002](docs/adr/0002-kustomize-over-helm.md) | Kustomize rather than Helm |
| [0003](docs/adr/0003-terraform-test-over-localstack.md) | Mocked `terraform test` rather than LocalStack |
| [0004](docs/adr/0004-irsa-over-node-roles.md) | IRSA rather than node instance roles |
| [0005](docs/adr/0005-s3-native-state-locking.md) | Native S3 state locking rather than a DynamoDB table |

Further reading: [architecture](docs/architecture.md),
[Well-Architected mapping](docs/well-architected.md),
[runbook](docs/runbook.md),
[conventions](docs/conventions.md).

## Licence

Apache-2.0. See [LICENSE](LICENSE).
