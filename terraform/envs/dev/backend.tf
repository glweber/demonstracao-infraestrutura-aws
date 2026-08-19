# Remote state for the development environment.
#
# State is held in S3 with native state locking. The lock is a conditional write of
# a `.tflock` object alongside the state file, which supersedes the DynamoDB lock
# table required by earlier versions and removes a resource from the bootstrap.
#
# The backend is intentionally left partially configured: the bucket name is an
# account-scoped value supplied at initialisation rather than committed here, which
# keeps the same configuration usable across accounts.
#
#   terraform init \
#     -backend-config="bucket=<state-bucket>" \
#     -backend-config="region=<region>"
#
# The bucket itself is created outside this configuration, since a configuration
# cannot store its own state in a bucket it has yet to create. It must have
# versioning enabled, public access blocked, and default encryption applied.
#
# Continuous integration validates this configuration with `-backend=false`, so no
# state is read and no credentials are required.

terraform {
  backend "s3" {
    key          = "environments/dev/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
