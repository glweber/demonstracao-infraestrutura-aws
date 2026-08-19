"""Validation rules applied to the runtime configuration."""

from __future__ import annotations

import pytest

from service.config import ConfigurationError, load_settings


def test_defaults_apply_when_environment_is_empty() -> None:
    settings = load_settings({})

    assert settings.environment == "development"
    assert settings.port == 8000
    assert settings.log_level == "INFO"


def test_values_are_read_from_the_supplied_mapping() -> None:
    settings = load_settings(
        {
            "APP_ENVIRONMENT": "production",
            "APP_SERVICE_NAME": "checkout",
            "APP_VERSION": "2.4.1",
            "APP_COMMIT_SHA": "abc1234",
            "APP_PORT": "9090",
            "APP_LOG_LEVEL": "warning",
        }
    )

    assert settings.environment == "production"
    assert settings.service_name == "checkout"
    assert settings.version == "2.4.1"
    assert settings.commit_sha == "abc1234"
    assert settings.port == 9090
    assert settings.log_level == "WARNING"


def test_settings_are_immutable() -> None:
    settings = load_settings({})

    with pytest.raises(AttributeError):
        settings.port = 1234  # type: ignore[misc]


@pytest.mark.parametrize(
    "environ",
    [
        pytest.param({"APP_PORT": "not-a-number"}, id="port-not-numeric"),
        pytest.param({"APP_PORT": "0"}, id="port-below-range"),
        pytest.param({"APP_PORT": "65536"}, id="port-above-range"),
        pytest.param({"APP_LOG_LEVEL": "verbose"}, id="unknown-log-level"),
        pytest.param({"APP_ENVIRONMENT": "   "}, id="blank-environment"),
    ],
)
def test_invalid_values_are_rejected(environ: dict[str, str]) -> None:
    with pytest.raises(ConfigurationError):
        load_settings(environ)
