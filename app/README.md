# demonstration-service

The workload the platform exists to run. It is deliberately small: its purpose is to
exercise the container, the cluster and the pipeline honestly, not to be interesting
in itself.

## Endpoints

| Path | Purpose |
| --- | --- |
| `/` | Build and runtime metadata: environment, version and source revision |
| `/healthz` | Liveness. Answers while the process can serve a request |
| `/readyz` | Readiness. Answers 503 before start-up completes and again once shutdown begins |
| `/metrics` | Prometheus exposition |
| `/docs` | Generated OpenAPI documentation |

The two probe endpoints are separate because they answer different questions, and
collapsing them causes real outages:

- Liveness performs **no dependency check**. A failure instructs the kubelet to
  restart the container, so a transient outage downstream must not reach it — the
  result would be a restart loop across every replica at once.
- Readiness reports whether **this instance** should receive traffic. Withdrawing it
  during shutdown is what allows the load balancer to drain connections before the
  process exits, and it is what the ALB target group health check is pointed at.

## Configuration

Every value is read from the environment; nothing is read from a file in the image,
so the same artefact runs unchanged in every environment.

| Variable | Default | Notes |
| --- | --- | --- |
| `APP_ENVIRONMENT` | `development` | Propagated to logs and metric labels |
| `APP_SERVICE_NAME` | `demonstration-service` | Logical identifier for observability |
| `APP_VERSION` | `0.0.0-dev` | Injected at build time from the release tag |
| `APP_COMMIT_SHA` | `unknown` | Injected at build time; traces a running image to its source |
| `APP_PORT` | `8000` | Must be within 1–65535 |
| `APP_LOG_LEVEL` | `INFO` | One of CRITICAL, ERROR, WARNING, INFO, DEBUG |

Invalid values raise `ConfigurationError` at start-up rather than degrading
silently, so a misconfigured deployment fails its readiness probe and is never
rotated into service.

## Logging

Records are emitted to standard output as single-line JSON. The `level` field
carries the level **name**, because the CloudWatch metric filter behind the error
rate alarm matches `{ $.level = "ERROR" }`. Changing that field to a numeric value
would silently disable the alarm.

Attributes passed through the `extra` argument are preserved in the payload;
internal record bookkeeping is not.

## Metrics

`http_requests_total` and `http_request_duration_seconds`, labelled by method, route
and status. The label carries the **route template** rather than the raw path, so
identifiers embedded in URLs cannot inflate cardinality. Unmatched paths collapse
into a single `unmatched` label.

## Development

```bash
make install    # editable install with the development extras
make lint-app   # ruff, ruff format, mypy in strict mode
make test-app   # pytest at a 100 % coverage gate, warnings treated as errors
```

Run it directly:

```bash
APP_ENVIRONMENT=local uvicorn service.main:app --reload --port 8000
```

## Tests

Twenty-five tests across three modules, holding coverage at 100 %:

- `test_config.py` — the validation rules at the configuration boundary, including
  every rejection path.
- `test_api.py` — endpoint contracts, and specifically that liveness and readiness
  diverge before start-up and after shutdown.
- `test_logging_setup.py` — the serialisation contract the alarm depends on,
  exception rendering, and handler installation.

The gate is set at 100 rather than below it: a threshold beneath the achieved level
only records how much regression is tolerated before anyone is told.
