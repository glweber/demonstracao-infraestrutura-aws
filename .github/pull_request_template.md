## Summary

<!-- What changes and why. Describe the change, not the process that produced it. -->

## Type of change

- [ ] Application
- [ ] Infrastructure (Terraform)
- [ ] Kubernetes manifests
- [ ] CI/CD
- [ ] Documentation

## Checklist

- [ ] `make lint` passes
- [ ] `make test` passes
- [ ] `make build` passes
- [ ] `make k8s-up verify` passes for changes touching `k8s/` or `docker/`
- [ ] Security controls unchanged, or the change is justified below
- [ ] Documentation and ADRs updated where a decision changed
- [ ] No credentials, secrets or account identifiers introduced

## Risk and rollback

<!-- Blast radius of this change and the procedure to revert it. -->
