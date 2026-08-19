# observability

Log collection, an error-rate metric filter, and an alarm with an SNS topic.

## Usage

```hcl
module "observability" {
  source = "../../modules/observability"

  name               = "demonstration-platform-prod"
  cluster_name       = module.eks.cluster_name
  log_retention_days = 365

  error_rate_threshold     = 10
  alarm_evaluation_periods = 2
  alarm_email_endpoints    = ["platform-oncall@example.com"]
}
```

## Behaviour worth knowing

- The alarm is driven by the application's own error rate, not by a synthetic health
  check. A health check confirms the endpoint answers; the error rate reveals that
  it is answering incorrectly, which is the failure a health check cannot see.
- The metric filter matches the structured `level` field of the JSON log line rather
  than scanning for a substring, so the word appearing inside a message body does not
  register as an error.
- `default_value = 0` means healthy periods publish a zero, which keeps the alarm out
  of `INSUFFICIENT_DATA`.
- `treat_missing_data = "breaching"`: a broken telemetry path raises the alarm rather
  than silencing it.
- `ok_actions` is set, so recovery is notified and an incident can be closed.

## Tests

`terraform test` — seven runs covering retention, encryption, the filter pattern,
the alarm's failure direction, topic encryption, and both variable validations.
