"""Run log: every command is a run, every unit of work a step, every check a result row."""
from __future__ import annotations

import logging
import time
from contextlib import contextmanager
from dataclasses import dataclass

import psycopg

log = logging.getLogger(__name__)


@dataclass
class CheckResult:
    check_name: str
    severity: str        # error | warning | info
    failed_rows: int
    detail: str

    @property
    def failed(self) -> bool:
        return self.failed_rows > 0

    @property
    def blocking(self) -> bool:
        return self.severity == "error" and self.failed


def start_run(conn: psycopg.Connection, command: str) -> int:
    return conn.execute(
        "INSERT INTO ops.run (command) VALUES (%s) RETURNING run_id", (command,)
    ).fetchone()[0]


def finish_run(conn: psycopg.Connection, run_id: int, ok: bool, message: str | None = None) -> None:
    conn.execute(
        "UPDATE ops.run SET finished_at = now(), status = %s, message = %s WHERE run_id = %s",
        ("succeeded" if ok else "failed", message, run_id),
    )


class Step:
    rows: int | None = None
    message: str | None = None


@contextmanager
def step(conn: psycopg.Connection, run_id: int, name: str, batch_id: int | None = None):
    step_id = conn.execute(
        "INSERT INTO ops.run_step (run_id, batch_id, step) VALUES (%s, %s, %s) RETURNING step_id",
        (run_id, batch_id, name),
    ).fetchone()[0]
    info, started = Step(), time.monotonic()
    label = f"{name}" + (f" (batch {batch_id})" if batch_id else "")
    log.info("-> %s ...", label)
    try:
        yield info
    except BaseException as exc:
        conn.execute(
            "UPDATE ops.run_step SET finished_at = now(), status = 'failed', message = %s WHERE step_id = %s",
            (str(exc)[:2000], step_id),
        )
        log.error("   failed after %.1fs: %s", time.monotonic() - started, exc)
        raise
    conn.execute(
        "UPDATE ops.run_step SET finished_at = now(), status = 'succeeded', rows_affected = %s, message = %s "
        "WHERE step_id = %s",
        (info.rows, info.message, step_id),
    )
    extra = f", {info.rows:,} rows" if info.rows is not None else ""
    suffix = f" - {info.message}" if info.message else ""
    log.info("   done in %.1fs%s%s", time.monotonic() - started, extra, suffix)


def record_checks(
    conn: psycopg.Connection, run_id: int, batch_id: int | None, results: list[CheckResult]
) -> None:
    for r in results:
        conn.execute(
            "INSERT INTO ops.check_result (run_id, batch_id, check_name, severity, failed_rows, detail) "
            "VALUES (%s, %s, %s, %s, %s, %s)",
            (run_id, batch_id, r.check_name, r.severity, r.failed_rows, r.detail),
        )
