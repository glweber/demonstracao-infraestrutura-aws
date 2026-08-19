"""Runtime configuration resolved exclusively from the process environment.

Configuration follows the twelve-factor principle: no value is read from a file
committed to the repository, and no credential is ever embedded in the image. The
container therefore remains identical across environments, and only the environment
supplied by the orchestrator differs.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Final

_VALID_LOG_LEVELS: Final[frozenset[str]] = frozenset(
    {"CRITICAL", "ERROR", "WARNING", "INFO", "DEBUG"}
)

_MIN_PORT: Final[int] = 1
_MAX_PORT: Final[int] = 65535


class ConfigurationError(ValueError):
    """Raised when the supplied environment cannot yield a valid configuration."""


@dataclass(frozen=True, slots=True)
class Settings:
    """Immutable view of the runtime configuration.

    Attributes:
        environment: Deployment stage name, propagated to logs and metrics labels.
        service_name: Logical service identifier used by observability tooling.
        version: Release identifier of the running artefact.
        commit_sha: Source revision the artefact was built from.
        port: TCP port the HTTP server binds to.
        log_level: Root logger threshold.

    """

    environment: str
    service_name: str
    version: str
    commit_sha: str
    port: int
    log_level: str


def load_settings(environ: dict[str, str] | None = None) -> Settings:
    """Build the settings object from the environment.

    Args:
        environ: Mapping to read from. Defaults to the process environment; an
            explicit mapping is accepted so that the validation rules remain
            testable without mutating global state.

    Returns:
        A validated, immutable settings object.

    Raises:
        ConfigurationError: If any value is absent when required, or out of range.

    """
    source = os.environ if environ is None else environ

    environment = source.get("APP_ENVIRONMENT", "development").strip()
    if not environment:
        raise ConfigurationError("APP_ENVIRONMENT must not be blank")

    log_level = source.get("APP_LOG_LEVEL", "INFO").strip().upper()
    if log_level not in _VALID_LOG_LEVELS:
        raise ConfigurationError(
            f"APP_LOG_LEVEL must be one of {sorted(_VALID_LOG_LEVELS)}, got {log_level!r}"
        )

    raw_port = source.get("APP_PORT", "8000").strip()
    try:
        port = int(raw_port)
    except ValueError as exc:
        raise ConfigurationError(f"APP_PORT must be an integer, got {raw_port!r}") from exc
    if not _MIN_PORT <= port <= _MAX_PORT:
        raise ConfigurationError(f"APP_PORT must be within {_MIN_PORT}-{_MAX_PORT}, got {port}")

    return Settings(
        environment=environment,
        service_name=source.get("APP_SERVICE_NAME", "demonstration-service").strip(),
        version=source.get("APP_VERSION", "0.0.0-dev").strip(),
        commit_sha=source.get("APP_COMMIT_SHA", "unknown").strip(),
        port=port,
        log_level=log_level,
    )
