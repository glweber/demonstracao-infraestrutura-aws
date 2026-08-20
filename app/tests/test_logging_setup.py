"""Behaviour of the structured logging configuration.

Log output is the only record a container leaves behind, and the alarm in the
observability module matches on the `level` field of these records. A regression in
the serialisation is therefore an operational failure, not a cosmetic one.
"""

from __future__ import annotations

import json
import logging
from collections.abc import Iterator
from types import TracebackType

import pytest

from service.logging_setup import JsonFormatter, configure_logging


@pytest.fixture(autouse=True)
def restore_root_logger() -> Iterator[None]:
    """Return the root logger to its prior state after each test."""
    root = logging.getLogger()
    handlers, level = root.handlers[:], root.level
    try:
        yield
    finally:
        root.handlers, root.level = handlers, level


ExcInfo = tuple[type[BaseException], BaseException, TracebackType | None]


def make_record(
    *,
    name: str = "service.main",
    level: int = logging.INFO,
    msg: object = "request completed",
    args: tuple[object, ...] | None = None,
    exc_info: ExcInfo | None = None,
) -> logging.LogRecord:
    """Build a log record with the fields a real emission would carry."""
    return logging.LogRecord(
        name=name,
        level=level,
        pathname="/opt/venv/service/main.py",
        lineno=42,
        msg=msg,
        args=args,
        exc_info=exc_info,
    )


def formatter() -> JsonFormatter:
    return JsonFormatter(service_name="demonstration-service", environment="test", version="1.0.0")


def test_a_record_serialises_to_a_single_json_line() -> None:
    output = formatter().format(make_record())

    assert "\n" not in output
    payload = json.loads(output)
    assert payload["message"] == "request completed"
    assert payload["logger"] == "service.main"


def test_the_level_field_is_the_name_the_metric_filter_matches() -> None:
    # The CloudWatch metric filter matches { $.level = "ERROR" }, so the field must
    # carry the level name rather than its numeric value.
    payload = json.loads(formatter().format(make_record(level=logging.ERROR)))

    assert payload["level"] == "ERROR"


def test_invariant_fields_are_attached_to_every_record() -> None:
    payload = json.loads(formatter().format(make_record()))

    assert payload["service"] == "demonstration-service"
    assert payload["environment"] == "test"
    assert payload["version"] == "1.0.0"
    assert "timestamp" in payload


def test_interpolation_arguments_are_applied() -> None:
    payload = json.loads(formatter().format(make_record(msg="served %s in %d ms", args=("/", 12))))

    assert payload["message"] == "served / in 12 ms"


def test_attributes_supplied_through_extra_are_preserved() -> None:
    record = make_record()
    record.request_id = "01J8Z9"
    record.status_code = 200

    payload = json.loads(formatter().format(record))

    assert payload["request_id"] == "01J8Z9"
    assert payload["status_code"] == 200


def test_reserved_record_attributes_are_not_leaked() -> None:
    payload = json.loads(formatter().format(make_record()))

    # Internal bookkeeping such as the source path and thread identifiers would
    # bloat every line without informing an operator.
    for reserved in ("pathname", "lineno", "msg", "args", "thread", "processName"):
        assert reserved not in payload


def test_an_exception_is_rendered_into_the_record() -> None:
    try:
        raise ValueError("upstream refused the connection")
    except ValueError as error:
        record = make_record(
            level=logging.ERROR,
            exc_info=(type(error), error, error.__traceback__),
        )

    payload = json.loads(formatter().format(record))

    assert "ValueError: upstream refused the connection" in payload["exception"]
    assert "Traceback" in payload["exception"]


def test_unserialisable_values_do_not_break_the_stream() -> None:
    record = make_record()
    record.connection = object()

    # A single bad value must not raise inside the logging path; losing the log
    # line would be worse than coercing the value to its string form.
    payload = json.loads(formatter().format(record))

    assert payload["connection"].startswith("<object object at")


def test_configuration_installs_exactly_one_handler() -> None:
    root = logging.getLogger()
    root.addHandler(logging.StreamHandler())
    root.addHandler(logging.StreamHandler())

    configure_logging("demonstration-service", "test", "1.0.0", "WARNING")

    assert len(root.handlers) == 1
    assert isinstance(root.handlers[0].formatter, JsonFormatter)
    assert root.level == logging.WARNING


def test_server_loggers_delegate_to_the_root_handler() -> None:
    access = logging.getLogger("uvicorn.access")
    access.addHandler(logging.StreamHandler())
    access.propagate = False

    configure_logging("demonstration-service", "test", "1.0.0", "INFO")

    for name in ("uvicorn", "uvicorn.access", "uvicorn.error"):
        server_logger = logging.getLogger(name)
        assert server_logger.handlers == []
        assert server_logger.propagate is True
