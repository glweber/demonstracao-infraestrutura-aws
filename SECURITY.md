# Security policy

## Scope

This repository is a reference implementation. It provisions no live infrastructure
and holds no production data, credentials or account identifiers. All AWS identifiers
appearing in configuration are placeholders.

## Reporting a vulnerability

Report suspected vulnerabilities through GitHub's private security advisory feature on
this repository. Do not open a public issue for an unfixed vulnerability.

Expected response times:

| Stage | Target |
| --- | --- |
| Acknowledgement | 3 working days |
| Initial assessment | 10 working days |
| Fix or documented mitigation | 90 days |

## Controls enforced in this repository

- Secret scanning on every commit through `gitleaks`, both locally via pre-commit and
  in continuous integration.
- Static analysis of infrastructure code with `tflint` and `checkov`; findings at
  HIGH or CRITICAL severity fail the build.
- Container image scanning with Trivy; the build fails on HIGH or CRITICAL findings
  that have a fix available.
- Third-party GitHub Actions pinned to a full commit SHA, mitigating tag mutation.
- Least-privilege `permissions` declared per workflow and per job.
- No long-lived cloud credentials. The AWS access path uses OIDC federation with a
  short-lived assumed role, and is disabled by default.

## Supported versions

The default branch is the only supported version.
