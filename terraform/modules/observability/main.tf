# Log collection and alerting for the workload.
#
# The alarm is deliberately driven by a metric filter over the application log
# stream rather than by a synthetic health check. A health check confirms that the
# endpoint answers; the error rate reveals that it is answering incorrectly, which
# is the failure mode a health check cannot see.

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  tags = merge(var.tags, {
    "Name"      = var.name
    "Module"    = "observability"
    "ManagedBy" = "terraform"
  })

  metric_namespace     = "Platform/${var.name}"
  metric_name          = "ApplicationErrors"
  alarm_period_seconds = 300
}

resource "aws_kms_key" "logs" {
  description             = "Encrypts the application log group for ${var.name}."
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.logs_key.json

  tags = local.tags
}

resource "aws_kms_alias" "logs" {
  name          = "alias/${var.name}-logs"
  target_key_id = aws_kms_key.logs.key_id
}

data "aws_iam_policy_document" "logs_key" {
  # checkov:skip=CKV_AWS_356:Key policies are scoped to the key they are attached to.
  # checkov:skip=CKV_AWS_109:Account root administration is mandatory on a KMS key.
  # checkov:skip=CKV_AWS_111:As above; service access is constrained by principal and
  # by the encryption context condition below.
  statement {
    sid       = "AllowAccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid = "AllowCloudWatchLogs"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]

    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.region}.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:*"]
    }
  }
}

resource "aws_cloudwatch_log_group" "application" {
  # checkov:skip=CKV_AWS_338:Retention is a per-environment decision surfaced as a
  # variable. Production sets 365 days; development accepts 30 deliberately.
  name              = "/aws/containerinsights/${var.cluster_name}/application"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.logs.arn

  tags = local.tags
}

# The application emits single-line JSON, so the filter matches on the structured
# level field rather than scanning for a substring, which would also match the word
# appearing inside a message body.
resource "aws_cloudwatch_log_metric_filter" "errors" {
  name           = "${var.name}-application-errors"
  log_group_name = aws_cloudwatch_log_group.application.name
  pattern        = "{ $.level = \"ERROR\" || $.level = \"CRITICAL\" }"

  metric_transformation {
    name      = local.metric_name
    namespace = local.metric_namespace
    value     = "1"
    # Absence of errors must publish a zero rather than no data, otherwise the alarm
    # sits in INSUFFICIENT_DATA whenever the service is healthy.
    default_value = 0
    unit          = "Count"
  }
}

resource "aws_sns_topic" "alarms" {
  name              = "${var.name}-alarms"
  kms_master_key_id = "alias/aws/sns"

  tags = local.tags
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.alarm_email_endpoints)

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_cloudwatch_metric_alarm" "error_rate" {
  alarm_name        = "${var.name}-application-error-rate"
  alarm_description = "Raised when the workload logs more than ${var.error_rate_threshold} errors per ${local.alarm_period_seconds / 60} minutes across ${var.alarm_evaluation_periods} consecutive periods."

  namespace   = local.metric_namespace
  metric_name = local.metric_name
  statistic   = "Sum"
  period      = local.alarm_period_seconds

  comparison_operator = "GreaterThanThreshold"
  threshold           = var.error_rate_threshold
  evaluation_periods  = var.alarm_evaluation_periods

  # Healthy periods publish zero, so missing data indicates a broken telemetry path
  # rather than a healthy service and must not be treated as success.
  treat_missing_data = "breaching"

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = local.tags
}
