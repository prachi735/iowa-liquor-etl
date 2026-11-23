"""Transform loaded batches: staging -> core (inside one transaction per batch, with batch
checks), then global checks, then rebuild the marts."""
from __future__ import annotations

import logging
import time

import psycopg

from . import ops
from .checks import ChecksFailed, print_results, run_checks
from .db import run_sql_file, set_batch, sql_files

log = logging.getLogger(__name__)


def pending_batches(conn: psycopg.Connection) -> list[int]:
    rows = conn.execute(
        "SELECT batch_id FROM ops.batch WHERE status = 'loaded' ORDER BY batch_id"
    ).fetchall()
    return [r[0] for r in rows]


def transform_batch(conn: psycopg.Connection, run_id: int, batch_id: int) -> None:
    results: list[ops.CheckResult] = []
    try:
        with ops.step(conn, run_id, "transform", batch_id) as info:
            with conn.transaction():
                set_batch(conn, batch_id)
                for path in sql_files("10_staging") + sql_files("20_core") + sql_files("25_rules"):
                    started = time.monotonic()
                    run_sql_file(conn, path)
                    log.info("   %-28s %6.1fs", path.name, time.monotonic() - started)
                results = run_checks(conn, "batch")
                if any(r.blocking for r in results):
                    raise ChecksFailed(results)  # rolls the whole batch back
                conn.execute(
                    "UPDATE ops.batch SET status = 'transformed', transformed_at = now() WHERE batch_id = %s",
                    (batch_id,),
                )
                info.rows = conn.execute("SELECT count(*) FROM staging.liquor_sales").fetchone()[0]
                info.message = summary(conn, batch_id)
    except ChecksFailed as exc:
        results = exc.results
        conn.execute("UPDATE ops.batch SET status = 'failed' WHERE batch_id = %s", (batch_id,))
        raise
    finally:
        if results:
            print_results(results)
            ops.record_checks(conn, run_id, batch_id, results)


def summary(conn: psycopg.Connection, batch_id: int) -> str:
    row = conn.execute(
        """
        SELECT count(*) FILTER (WHERE first_batch_id = %(b)s AND changed_batch_id IS NULL),
               count(*) FILTER (WHERE changed_batch_id = %(b)s),
               count(*) FILTER (WHERE deleted_batch_id = %(b)s),
               count(*) FILTER (WHERE last_batch_id = %(b)s AND first_batch_id <> %(b)s
                                AND changed_batch_id IS DISTINCT FROM %(b)s)
        FROM core.invoice
        """,
        {"b": batch_id},
    ).fetchone()
    return f"invoices new {row[0]:,}, changed {row[1]:,}, deleted {row[2]:,}, unchanged {row[3]:,}"


def global_checks(conn: psycopg.Connection, run_id: int) -> None:
    with ops.step(conn, run_id, "global checks"):
        results = run_checks(conn, "global")
        print_results(results)
        ops.record_checks(conn, run_id, None, results)
        if any(r.blocking for r in results):
            raise ChecksFailed(results)


def apply_rules(conn: psycopg.Connection, run_id: int) -> None:
    """Re-apply the rule tables to the dimensions, e.g. after editing a store type rule."""
    with ops.step(conn, run_id, "apply rules"):
        with conn.transaction():
            for path in sql_files("25_rules"):
                run_sql_file(conn, path)


def build_marts(conn: psycopg.Connection, run_id: int) -> None:
    with ops.step(conn, run_id, "build marts") as info:
        with conn.transaction():
            for path in sql_files("30_marts"):
                run_sql_file(conn, path)
        info.rows = len(sql_files("30_marts"))
        info.message = "tables rebuilt"


def transform_all(conn: psycopg.Connection, run_id: int, marts: bool = True) -> int:
    batches = pending_batches(conn)
    if not batches:
        log.info("   no batches waiting to be transformed")
    for batch_id in batches:
        transform_batch(conn, run_id, batch_id)
    global_checks(conn, run_id)
    if marts:
        build_marts(conn, run_id)
    return len(batches)
