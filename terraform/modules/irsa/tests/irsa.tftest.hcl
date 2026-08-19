# Unit tests for the IRSA module.
#
# These assertions guard the trust policy, which is the entire security boundary of
# the module. A regression here would silently widen which workloads can assume the
# role, without any resource being added or removed.

mock_provider "aws" {}

variables {
  role_name            = "demo-platform-service"
  oidc_provider_arn    = "arn:aws:iam::111122223333:oidc-provider/oidc.eks.eu-west-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
  oidc_provider_url    = "oidc.eks.eu-west-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
  namespace            = "demonstration"
  service_account_name = "demonstration-service"
}

run "trust_is_bound_to_one_service_account" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition.StringEquals["oidc.eks.eu-west-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE:sub"] == "system:serviceaccount:demonstration:demonstration-service"
    error_message = "The subject condition must name exactly one namespace and service account."
  }

  assert {
    condition     = !can(jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition.StringLike)
    error_message = "A StringLike condition would permit wildcard subjects and must not be present."
  }
}

run "audience_is_restricted_to_sts" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition.StringEquals["oidc.eks.eu-west-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE:aud"] == "sts.amazonaws.com"
    error_message = "The audience condition must be present and restricted to sts.amazonaws.com."
  }
}

run "web_identity_federation_is_the_only_permitted_action" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity"
    error_message = "Only web identity federation may be permitted by the trust policy."
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal.Federated == var.oidc_provider_arn
    error_message = "The federated principal must be the cluster OIDC provider."
  }
}

run "credentials_are_short_lived_by_default" {
  command = plan

  assert {
    condition     = aws_iam_role.this.max_session_duration == 3600
    error_message = "The default session duration must not exceed one hour."
  }
}

run "no_policy_is_attached_unless_requested" {
  command = plan

  assert {
    condition     = length(aws_iam_role_policy_attachment.managed) == 0
    error_message = "The module must grant no permissions by default."
  }

  assert {
    condition     = length(aws_iam_role_policy.inline) == 0
    error_message = "No inline policy may be created unless one is supplied."
  }
}

run "supplied_policies_are_attached" {
  command = plan

  variables {
    policy_arns        = ["arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"]
    inline_policy_json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.managed) == 1
    error_message = "Managed policies supplied by the caller must be attached."
  }

  assert {
    condition     = length(aws_iam_role_policy.inline) == 1
    error_message = "An inline policy supplied by the caller must be created."
  }
}

run "rejects_an_issuer_url_carrying_a_scheme" {
  command = plan

  variables {
    oidc_provider_url = "https://oidc.eks.eu-west-1.amazonaws.com/id/EXAMPLE"
  }

  expect_failures = [var.oidc_provider_url]
}

run "rejects_a_session_duration_beyond_the_permitted_ceiling" {
  command = plan

  variables {
    max_session_duration_seconds = 86400
  }

  expect_failures = [var.max_session_duration_seconds]
}
