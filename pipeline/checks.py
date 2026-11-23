"""Data checks. Each file in sql/90_checks/<scope>/ is one SELECT returning
check_name, severity, failed_rows, detail. An 'error' with failed rows stops the run."""
from __future__ import annotations

import logging

import psycopg

from .db import PipelineError, sql_files
from .ops import CheckResult

log = logging.getLogger(__name__)


class ChecksFailed(PipelineError):
    def __init__(self, results: list[CheckResult]):
        self.results = results
        failed = [r for r in results if r.blocking]
        super().__init__("; ".join(f"{r.check_name}: {r.detail}" for r in failed))


def run_checks(conn: psycopg.Connection, scope: str) -> list[CheckResult]:
    results = []
    for path in sql_files(f"90_checks/{scope}"):
        try:
            rows = conn.execute(path.read_text(encoding="utf-8")).fetchall()
        except psycopg.Error as exc:
            raise PipelineError(f"{path.name}: {exc}") from exc
        results += [CheckResult(str(n), str(s), int(f or 0), str(d or "")) for n, s, f, d in rows]
    return results


def print_results(results: list[CheckResult]) -> None:
    for r in results:
        if r.blocking:
            log.error("   [FAIL] %s: %s", r.check_name, r.detail)
        elif r.failed and r.severity == "warning":
            log.warning("   [warn] %s: %s", r.check_name, r.detail)
        elif r.failed:
            log.info("   [note] %s: %s", r.check_name, r.detail)
        else:
            log.info("   [ ok ] %s: %s", r.check_name, r.detail)
