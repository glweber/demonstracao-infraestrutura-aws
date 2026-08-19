# 2. Kustomize rather than Helm

- Status: Accepted
- Date: 2026-08-19

## Context

The workload manifests must vary between environments: image reference, replica
count, resource sizing, the presence of an Ingress, and the IRSA annotation. Helm
and Kustomize are both established answers.

## Decision

Use Kustomize, through `kubectl kustomize` and `kubectl apply -k`.

## Rationale

- The output of `kustomize build` is plain YAML that can be read and diffed. A Helm
  chart's output only exists after templating, so review happens on a template
  rather than on what will be applied.
- Kustomize patches are themselves valid Kubernetes objects, so they are checked
  against the schema. A Helm template is text until rendered, and a mistake inside
  `{{ }}` is discovered at release time.
- No additional tool is required: `kubectl` includes Kustomize. Helm would add a
  binary, a release history stored in cluster secrets, and a second lifecycle to
  operate.
- The variation here is small and structural. Templating earns its complexity when
  a chart must serve consumers whose requirements are unknown, which is not the
  case for a workload owned by the team deploying it.

## Consequences

**Accepted.** No packaging or distribution story: this workload cannot be published
as a chart for third parties. No conditional logic, so a genuinely optional
component would need its own overlay rather than a flag.

**Gained.** Fewer tools, schema-checked patches, and a rendered manifest that can be
validated by `kubeconform` before it reaches a cluster.

If the platform later needs to distribute a component to teams outside this
repository, that component gets a chart; this decision is not a prohibition on Helm
elsewhere.
