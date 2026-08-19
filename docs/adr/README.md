# Architecture decision records

One record per decision that a reader would otherwise have to reverse engineer from
the configuration. Records are immutable once accepted: a decision that changes is
superseded by a new record rather than edited in place, so the reasoning that
applied at the time remains legible.

Format: [MADR](https://adr.github.io/madr/).

| ADR | Decision | Status |
| --- | --- | --- |
| [0001](0001-eks-over-ecs.md) | EKS rather than ECS | Accepted |
| [0002](0002-kustomize-over-helm.md) | Kustomize rather than Helm | Accepted |
| [0003](0003-terraform-test-over-localstack.md) | Mocked `terraform test` rather than LocalStack | Accepted |
| [0004](0004-irsa-over-node-roles.md) | IRSA rather than node instance roles | Accepted |
| [0005](0005-s3-native-state-locking.md) | Native S3 state locking rather than a DynamoDB table | Accepted |
