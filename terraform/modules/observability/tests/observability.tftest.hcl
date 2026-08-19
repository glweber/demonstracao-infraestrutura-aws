# Unit tests for the observability module.

mock_provider "aws" {}

override_data {
  target = data.aws_iam_policy_document.logs_key
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

variables {
  name         = "demo-platform"
  cluster_name = "demo-platform"
  tags         = { Environment = "test" }
}

run "logs_are_encrypted_and_retained_for_a_bounded_period" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.application.retention_in_days == 30
    error_message = "Log retention must be explicit; the default of never expiring accrues cost indefinitely."
  }

  assert {
    condition     = aws_kms_key.logs.enable_key_rotation
    error_message = "The log encryption key must rotate automatically."
  }
}

run "the_error_filter_matches_the_structured_level_field" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_metric_filter.errors.pattern == "{ $.level = \"ERROR\" || $.level = \"CRITICAL\" }"
    error_message = "The filter must match the JSON level field rather than scanning for a substring."
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.errors.metric_transformation[0].default_value == "0"
    error_message = "Healthy periods must publish zero so that the alarm leaves INSUFFICIENT_DATA."
  }
}

run "the_alarm_fails_towards_alerting" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.error_rate.treat_missing_data == "breaching"
    error_message = "A broken telemetry path must raise the alarm rather than silence it."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.error_rate.evaluation_periods >= 2
    error_message = "A single anomalous period must not page anyone."
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.error_rate.ok_actions) == 1
    error_message = "Recovery must be notified as well as failure, so that an incident can be closed."
  }
}

run "the_alarm_topic_is_encrypted" {
  command = plan

  assert {
    condition     = aws_sns_topic.alarms.kms_master_key_id == "alias/aws/sns"
    error_message = "The alarm topic must be encrypted at rest."
  }
}

run "subscriptions_are_created_only_when_addresses_are_supplied" {
  command = plan

  assert {
    condition     = length(aws_sns_topic_subscription.email) == 0
    error_message = "No subscription may be created without an explicit address."
  }
}

run "rejects_an_unactionable_threshold" {
  command = plan

  variables {
    error_rate_threshold = 0
  }

  expect_failures = [var.error_rate_threshold]
}

run "rejects_a_single_evaluation_period" {
  command = plan

  variables {
    alarm_evaluation_periods = 1
  }

  expect_failures = [var.alarm_evaluation_periods]
}
