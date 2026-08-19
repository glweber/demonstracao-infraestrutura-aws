"""Behaviour of the HTTP endpoints, including the probe semantics."""

from __future__ import annotations

from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient

from service.config import load_settings
from service.main import create_app

_ENVIRON = {
    "APP_ENVIRONMENT": "test",
    "APP_SERVICE_NAME": "demonstration-service",
    "APP_VERSION": "1.0.0",
    "APP_COMMIT_SHA": "deadbee",
}


@pytest.fixture
def client() -> Iterator[TestClient]:
    """Provide a client whose context manager drives the lifespan hooks."""
    with TestClient(create_app(load_settings(_ENVIRON))) as running_client:
        yield running_client


def test_root_returns_build_metadata(client: TestClient) -> None:
    response = client.get("/")

    assert response.status_code == 200
    assert response.json()["commit"] == "deadbee"
    assert response.json()["environment"] == "test"


def test_liveness_succeeds_while_serving(client: TestClient) -> None:
    assert client.get("/healthz").status_code == 200


def test_readiness_succeeds_after_startup(client: TestClient) -> None:
    assert client.get("/readyz").status_code == 200


def test_readiness_fails_before_startup_completes() -> None:
    # Bypassing the context manager leaves the lifespan hooks unrun, reproducing the
    # window between container start and application readiness.
    unstarted = TestClient(create_app(load_settings(_ENVIRON)))

    assert unstarted.get("/readyz").status_code == 503


def test_liveness_and_readiness_diverge_during_shutdown() -> None:
    app = create_app(load_settings(_ENVIRON))
    with TestClient(app) as running:
        assert running.get("/readyz").status_code == 200

    # After the lifespan exits, readiness must be withdrawn so that the load
    # balancer drains the instance, while liveness remains a separate concern.
    stopped = TestClient(app)
    assert stopped.get("/readyz").status_code == 503
    assert stopped.get("/healthz").status_code == 200


def test_metrics_expose_the_request_counter(client: TestClient) -> None:
    client.get("/healthz")

    body = client.get("/metrics").text

    assert "http_requests_total" in body
    assert "http_request_duration_seconds" in body


def test_metric_labels_use_the_route_template(client: TestClient) -> None:
    client.get("/does-not-exist")

    body = client.get("/metrics").text

    # Unmatched paths collapse into a single label value, bounding cardinality.
    assert 'path="unmatched"' in body
