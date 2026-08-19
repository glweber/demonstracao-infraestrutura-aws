"""HTTP surface of the demonstration service.

Three endpoints exist to satisfy distinct orchestration contracts and must not be
collapsed into one:

* ``/healthz``  liveness. Answers as long as the process can serve a request. A
  failure here instructs the kubelet to restart the container, so it deliberately
  performs no dependency checks; a transient dependency outage must not trigger a
  restart loop.
* ``/readyz``   readiness. Reports whether the instance should receive traffic. It
  returns 503 before start-up completes and again once shutdown begins, which is what
  allows the load balancer to drain connections before the process exits.
* ``/metrics``  Prometheus exposition for scraping.
"""

from __future__ import annotations

import logging
import time
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import asynccontextmanager
from typing import Final

from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

from service import __version__
from service.config import Settings, load_settings
from service.logging_setup import configure_logging

_LOGGER: Final[logging.Logger] = logging.getLogger(__name__)

REQUEST_COUNT: Final[Counter] = Counter(
    "http_requests_total",
    "Total number of HTTP requests handled.",
    labelnames=("method", "path", "status"),
)

REQUEST_LATENCY: Final[Histogram] = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds.",
    labelnames=("method", "path"),
)


class ServiceState:
    """Mutable readiness flag shared between the lifespan hooks and the endpoints."""

    def __init__(self) -> None:
        """Start in the unready state; readiness is granted once start-up finishes."""
        self.ready: bool = False


def create_app(settings: Settings | None = None) -> FastAPI:
    """Construct the ASGI application.

    Accepting an optional settings object keeps the application constructible under
    test without reaching for the process environment.
    """
    resolved = load_settings() if settings is None else settings
    configure_logging(
        service_name=resolved.service_name,
        environment=resolved.environment,
        version=resolved.version,
        level=resolved.log_level,
    )
    state = ServiceState()

    @asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        """Gate readiness around the serving window."""
        _LOGGER.info("service starting", extra={"event": "startup"})
        state.ready = True
        try:
            yield
        finally:
            # Withdrawing readiness before the socket closes gives the load
            # balancer time to stop routing new connections to this instance.
            state.ready = False
            _LOGGER.info("service stopping", extra={"event": "shutdown"})

    app = FastAPI(
        title=resolved.service_name,
        version=resolved.version,
        lifespan=lifespan,
        docs_url="/docs",
        redoc_url=None,
    )

    @app.middleware("http")
    async def record_metrics(
        request: Request, call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        """Time every request and record its outcome.

        The route template is used as the label value rather than the raw path, so
        that identifiers embedded in URLs cannot inflate metric cardinality.
        """
        started = time.perf_counter()
        response = await call_next(request)
        route = request.scope.get("route")
        path = getattr(route, "path", "unmatched")
        REQUEST_COUNT.labels(request.method, path, str(response.status_code)).inc()
        REQUEST_LATENCY.labels(request.method, path).observe(time.perf_counter() - started)
        return response

    @app.get("/", summary="Build and runtime metadata")
    async def root() -> dict[str, str]:
        """Return the identity of the running artefact."""
        return {
            "service": resolved.service_name,
            "environment": resolved.environment,
            "version": resolved.version,
            "commit": resolved.commit_sha,
            "package_version": __version__,
        }

    @app.get("/healthz", summary="Liveness probe")
    async def healthz() -> dict[str, str]:
        """Confirm the process is able to serve requests."""
        return {"status": "alive"}

    @app.get("/readyz", summary="Readiness probe")
    async def readyz() -> Response:
        """Report whether this instance should receive traffic."""
        if not state.ready:
            return JSONResponse(status_code=503, content={"status": "not-ready"})
        return JSONResponse(status_code=200, content={"status": "ready"})

    @app.get("/metrics", summary="Prometheus exposition", include_in_schema=False)
    async def metrics() -> Response:
        """Expose the collected metrics in the Prometheus text format."""
        return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)

    return app


app = create_app()
