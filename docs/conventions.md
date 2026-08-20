# Conventions

The standards every change in this repository is held to. They are enforced by the
pre-commit hooks and by the pipelines, not by convention alone.

## Language

Code, comments, docstrings, test names, log messages, commit messages and
documentation are written in **British English** (`behaviour`, `initialise`,
`serialise`, `licence` as a noun). The `LICENSE` file retains the American spelling
because it is a filename convention that hosting platforms detect.

## Comments

A comment explains **what the code does and why**, in an impersonal, technical
register. It documents the decision, not the author and not the process that led
there.

Forbidden: the first person, narratives of authorship, histories of attempts,
promotional or conversational language, and any comment that merely restates the
line below it.

```python
# Correct
# Retry uses exponential backoff; the API rate-limits bursts above 10 req/s.

# Incorrect
# I added a retry here because it was failing before and now it works.
```

Where a deliberate limitation exists, the comment names the constraint and the
upgrade path, so that the shortcut is legible as a decision rather than an
oversight:

```yaml
# Limitation: the default kind CNI does not implement NetworkPolicy, so continuous
# integration proves only that these objects are schema-valid and admitted.
# Enforcement is exercised on EKS, where the VPC CNI applies them.
```

## Standards applied

| Standard | Applied to |
| --- | --- |
| PEP 8, PEP 257, PEP 484 | Python style, docstrings and type annotations; enforced by `ruff` and `mypy --strict` |
| PEP 621 | Project metadata in `pyproject.toml` |
| ISO/IEC 25010 | Quality attributes — maintainability, reliability, security — used as review criteria |
| IEEE 1016 | Design documentation, recorded as ADRs in `docs/adr/` |
| ISO 8601 | Dates and timestamps; UTC is the canonical zone in persistence |
| RFC 1123 | Kubernetes name validation in Terraform variables |
| RFC 5737 | Reserved address ranges used for every documented example |
| OCI image spec | Image annotations in `docker/Dockerfile` |
| Semantic Versioning | Release tags (`v1.2.3`) |
| Conventional module structure | `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `README.md` per Terraform module |

## Rules

- Validate input at every trust boundary. Handle errors explicitly; never suppress
  them.
- No credential, secret or account identifier in code, logs or git history.
  Configuration comes from the environment.
- Non-trivial logic — a branch, a loop, a parser, a monetary calculation, a security
  path — ships with an executable test.
- Quality gates are set at the level actually achieved, never below it. A threshold
  beneath the current standard only records how much regression is tolerated before
  anyone is told. Python coverage is therefore gated at 100 %, and warnings are
  errors.
- Complexity requires a recorded justification. Simplicity is the default.
- Commit messages are impersonal and imperative, describing the change rather than
  the process. No co-authorship trailers and no tool attribution.
- Every Terraform variable is typed and described; every output is described.
  Validation blocks encode the constraints that would otherwise fail at apply time.
- Third-party GitHub Actions are pinned to a full commit SHA, never to a tag.

## Publication

Nothing from this repository is published to any external service: no image
registry, no paste service, no artefact host. Deliverables remain files in the
repository. The AWS deployment path exists in configuration and is deliberately
left dormant.
