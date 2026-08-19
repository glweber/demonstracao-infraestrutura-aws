# ecr

Container registry with immutable tags, scan-on-push, and a lifecycle policy that
bounds storage growth.

## Usage

```hcl
module "ecr" {
  source = "../../modules/ecr"

  name                         = "demonstration-service"
  untagged_image_expiry_days   = 7
  retained_release_image_count = 50
  kms_key_arn                  = aws_kms_key.artefacts.arn
}
```

## Behaviour worth knowing

- Tags are immutable. A deployed tag cannot be repointed at different content after
  the fact, which is what makes an image reference in a manifest auditable and a
  rollback to a known tag trustworthy.
- `force_delete` is off, so a repository holding images cannot be removed in one
  step.
- Retention is validated to keep at least three release images, so a rollback target
  always exists.
- Without `kms_key_arn` the repository uses AES256 with the AWS-managed key.

## Tests

`terraform test` — five runs covering the supply-chain controls, both encryption
modes, the lifecycle policy, and the retention validation.
