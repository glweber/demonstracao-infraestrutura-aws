# IAM Roles for Service Accounts.
#
# The workload obtains AWS credentials through the cluster's OIDC provider, which
# exchanges a projected service account token for short-lived STS credentials. No
# access key is ever created, stored or rotated, and the credential is scoped to a
# single service account rather than to the node it happens to run on. Granting
# permissions to the node instance profile instead would extend them to every pod
# scheduled onto that node.
#
# The trust policy is written with jsonencode rather than assembled from an
# aws_iam_policy_document data source. The two conditions below are the entirety of
# the security boundary, so they are kept literal and directly assertable in the
# module's tests.

locals {
  tags = merge(var.tags, {
    "Name"      = var.role_name
    "Module"    = "irsa"
    "ManagedBy" = "terraform"
  })

  subject = "system:serviceaccount:${var.namespace}:${var.service_account_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "sts:AssumeRoleWithWebIdentity"
        Principal = { Federated = var.oidc_provider_arn }
        Condition = {
          StringEquals = {
            # Binds the role to exactly one service account in one namespace. A
            # StringLike comparison with a wildcard here would let any service
            # account in the cluster assume the role.
            "${var.oidc_provider_url}:sub" = local.subject

            # Without the audience check a token minted for another relying party
            # would be accepted, which is the documented confused-deputy path.
            "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
          }
        }
      },
    ]
  })
}

resource "aws_iam_role" "this" {
  name                 = var.role_name
  description          = "Assumed by ${local.subject} through the cluster OIDC provider."
  assume_role_policy   = local.assume_role_policy
  max_session_duration = var.max_session_duration_seconds

  # Caps the effective permissions of the role regardless of any policy attached to
  # it later, bounding the blast radius of an over-permissive grant.
  permissions_boundary = var.permissions_boundary_arn

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = toset(var.policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "inline" {
  count = var.inline_policy_json == null ? 0 : 1

  name   = "${var.role_name}-inline"
  role   = aws_iam_role.this.id
  policy = var.inline_policy_json
}
