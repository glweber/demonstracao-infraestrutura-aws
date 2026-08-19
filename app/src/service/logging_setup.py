"""Structured logging emitted to standard output as single-line JSON.

Container workloads must not manage log files. Records are written to standard
output and collected by the node agent, which is the contract expected by
CloudWatch Logs and by every mainstream log shipper.
"""

from __future__ import annotations

import json
import logging
import sys
from typing import Any

_RESERVED_RECORD_KEYS: frozenset[str] = frozenset(
    logging.LogRecord("", 0, "", 0, "", None, None).__dict__
)


class JsonFormatter(logging.Formatter):
    """Render log records as JSON objects with a stable key set."""

    def __init__(self, service_name: str, environment: str, version: str) -> None:
        """Bind the invariant fields attached to every emitted record."""
        super().__init__()
        self._static: dict[str, str] = {
            "service": service_name,
            "environment": environment,
            "version": version,
        }

    def format(self, record: logging.LogRecord) -> str:
        """Serialise a single record."""
        payload: dict[str, Any] = {
            "timestamp": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            **self._static,
        }
        # Any attribute injected through the `extra` argument is preserved.
        payload.update(
            {
                key: value
                for key, value in record.__dict__.items()
                if key not in _RESERVED_RECORD_KEYS
            }
        )
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, default=str, separators=(",", ":"))


def configure_logging(service_name: str, environment: str, version: str, level: str) -> None:
    """Install the JSON formatter on the root logger.

    Existing handlers are replaced so that the process emits exactly one stream,
    avoiding the duplicate records produced when a framework installs its own
    handler alongside the default one.
    """
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter(service_name, environment, version))

    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(level)

    # Uvicorn installs its own handlers; delegating to the root logger keeps the
    # output format uniform across application and server records.
    for name in ("uvicorn", "uvicorn.access", "uvicorn.error"):
        server_logger = logging.getLogger(name)
        server_logger.handlers = []
        server_logger.propagate = True
