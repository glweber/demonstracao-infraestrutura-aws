# Architecture

## Topology

```mermaid
graph TB
    subgraph internet[" "]
        client[Client]
    end

    subgraph aws["AWS account · eu-west-1"]
        subgraph vpc["VPC 10.20.0.0/16"]
            alb["Application Load Balancer<br/>internet-facing · TLS 1.3"]

            subgraph public["Public subnets · one per zone"]
                natgw["NAT gateways<br/>one per zone"]
            end

            subgraph private["Private subnets · one per zone"]
                subgraph eks["EKS managed node group"]
                    pod1["service<br/>zone a"]
                    pod2["service<br/>zone b"]
                    pod3["service<br/>zone c"]
                end
            end
        end

        cp["EKS control plane<br/>secrets encrypted with KMS<br/>audit log to CloudWatch"]
        ecr["ECR<br/>immutable tags · scan on push"]
        oidc["IAM OIDC provider<br/>IRSA"]
        cw["CloudWatch<br/>logs · metric filter · alarm"]
        sns["SNS alarm topic"]
    end

    client -->|HTTPS 443| alb
    alb -->|target-type ip → :8000| pod1
    alb --> pod2
    alb --> pod3

    pod1 -.->|egress| natgw
    cp <-->|private endpoint| private
    private -->|image pull| ecr
    pod1 -.->|assume role with web identity| oidc
    pod1 -.->|stdout| cw
    cw --> sns

    classDef plane fill:#1f2937,stroke:#4b5563,color:#f9fafb
    classDef net fill:#0f766e,stroke:#134e4a,color:#f0fdfa
    class cp,ecr,oidc,cw,sns plane
    class alb,natgw net
```

## Request path

1. The client resolves the record and connects to the Application Load Balancer over
   TLS 1.3. The load balancer is the only internet-facing component.
2. The AWS Load Balancer Controller has registered pod IP addresses directly in the
   target group (`target-type: ip`), so the request reaches a container without a
   second hop through a node port.
3. Targets are health-checked against `/readyz`, not `/healthz`. A draining instance
   withdraws readiness and is removed from rotation while it is still serving its
   in-flight requests.
4. The pod runs in a private subnet as UID 10001, on a read-only root filesystem,
   with every Linux capability dropped, under the `restricted` Pod Security
   Admission profile.

## Trust boundaries

| Boundary | Control |
| --- | --- |
| Internet to load balancer | Security group; TLS 1.3 policy; invalid header fields dropped |
| Load balancer to pod | NetworkPolicy admits port 8000 only; default deny for everything else |
| Pod to AWS API | IRSA: a token scoped to one service account, exchanged for credentials valid for 15 minutes |
| Pod to node metadata | IMDSv2 required, hop limit 1 — the container cannot reach the metadata service |
| Node to control plane | Private endpoint; public endpoint restricted to an explicit allow-list |
| Control plane to etcd | Secrets encrypted with a customer-managed KMS key that rotates automatically |

## Failure domains

The platform spans three availability zones. Each holds one public subnet, one
private subnet, its own NAT gateway and at least one replica, and the production
overlay sets `whenUnsatisfiable: DoNotSchedule` on the zonal spread constraint so a
schedule that would concentrate replicas fails loudly instead.

Losing a zone therefore removes one third of capacity: the surviving zones keep
their own egress path, the load balancer stops targeting the lost addresses within
two failed health checks, and the autoscaler replaces the capacity in the zones that
remain.

The development environment deliberately trades this away — one NAT gateway, spot
capacity, `ScheduleAnyway` — and each trade-off is annotated at the point it is made
in `terraform/envs/dev/main.tf`.

## Deployment flow

```mermaid
sequenceDiagram
    participant Dev as Engineer
    participant GH as GitHub Actions
    participant K as kind (in-runner)
    participant AWS as AWS (dormant)

    Dev->>GH: push
    GH->>GH: ruff · mypy · pytest
    GH->>GH: build image · hadolint · Trivy · SBOM
    GH->>GH: terraform validate · tflint · checkov · terraform test (mocked)
    GH->>K: create cluster · load image · apply dev overlay
    K-->>GH: rollout complete
    GH->>K: smoke test — endpoints and security context
    GH--xAWS: publish job skipped (AWS_ROLE_ARN unset)
```

## What is intentionally absent

- **A service mesh.** The workload is a single service; mTLS between one service and
  itself buys nothing that a NetworkPolicy does not already provide.
- **A GitOps controller.** Argo CD or Flux would be the next step for a real
  platform, but the deployment path here terminates at a cluster that CI creates and
  destroys within the same job.
- **Multi-region.** The recovery objectives that would justify the second region
  have not been stated, and inventing them would produce architecture without a
  requirement behind it.
