"""Load CSV files into raw.liquor_sales exactly as delivered, one batch per file.

A file whose SHA-256 is already in ops.batch is skipped, so re-running a load is safe."""
from __future__ import annotations

import csv
import hashlib
import logging
from pathlib import Path

import psycopg
from psycopg import sql

from . import config, ops
from .db import PipelineError

CHUNK = 1 << 20
log = logging.getLogger(__name__)


class SchemaDriftError(PipelineError):
    """The file's columns differ from the 23 the pipeline expects."""


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        while chunk := f.read(CHUNK):
            digest.update(chunk)
    return digest.hexdigest()


def read_header(path: Path) -> list[str]:
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        header = next(csv.reader(f), [])
    return [h.strip().lower() for h in header]


def check_header(header: list[str]) -> None:
    expected = set(config.EXPECTED_COLUMNS)
    missing, extra = expected - set(header), set(header) - expected
    if missing or extra or len(header) != len(set(header)):
        raise SchemaDriftError(
            "Column mismatch: "
            + (f"missing {sorted(missing)} " if missing else "")
            + (f"unexpected {sorted(extra)} " if extra else "")
            + ("duplicate column names" if len(header) != len(set(header)) else "")
        )


def load_file(conn: psycopg.Connection, run_id: int, path: Path, source: str | None = None) -> int | None:
    """Load one CSV; returns the new batch id, or None when the file was loaded before."""
    path = Path(path)
    digest = sha256(path)
    row = conn.execute(
        "SELECT batch_id, status FROM ops.batch WHERE file_sha256 = %s", (digest,)
    ).fetchone()
    if row:
        log.info("   %s: already loaded as batch %s (%s), skipped", path.name, row[0], row[1])
        return None

    header = read_header(path)
    check_header(header)
    header_cols = sql.SQL(", ").join(sql.Identifier(c) for c in header)
    expected_cols = sql.SQL(", ").join(sql.Identifier(c) for c in config.EXPECTED_COLUMNS)

    with ops.step(conn, run_id, f"load {path.name}") as info:
        with conn.transaction():
            batch_id = conn.execute(
                "INSERT INTO ops.batch (run_id, source_name, file_name, file_sha256, file_bytes) "
                "VALUES (%s, %s, %s, %s, %s) RETURNING batch_id",
                (run_id, source or path.stem, path.name, digest, path.stat().st_size),
            ).fetchone()[0]
            conn.execute("TRUNCATE raw.liquor_sales_landing RESTART IDENTITY")
            with conn.cursor() as cur:
                copy_stmt = sql.SQL(
                    "COPY raw.liquor_sales_landing ({cols}) "
                    "FROM STDIN WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')"
                ).format(cols=header_cols)
                with cur.copy(copy_stmt) as copy:
                    with path.open("rb") as f:
                        while chunk := f.read(CHUNK):
                            copy.write(chunk)
            insert_stmt = sql.SQL(
                "INSERT INTO raw.liquor_sales (batch_id, row_no, {cols}) "
                "SELECT %s::bigint, row_no, {cols} FROM raw.liquor_sales_landing"
            ).format(cols=expected_cols)
            rows = conn.execute(insert_stmt, (batch_id,)).rowcount
            conn.execute(
                "UPDATE ops.batch SET rows_loaded = %s WHERE batch_id = %s", (rows, batch_id)
            )
            conn.execute("TRUNCATE raw.liquor_sales_landing")
        info.rows, info.message = rows, f"batch {batch_id}"
    return batch_id


def prune_raw(conn: psycopg.Connection, keep: int | None = None) -> int:
    """Delete raw rows of transformed batches, keeping the newest `keep` per source."""
    keep = config.RAW_KEEP_BATCHES if keep is None else keep
    return conn.execute(
        """
        DELETE FROM raw.liquor_sales r
        USING (
            SELECT batch_id FROM (
                SELECT batch_id, row_number() OVER (
                    PARTITION BY regexp_replace(source_name, '_\\d{4}-\\d{2}-\\d{2}$', '')
                    ORDER BY batch_id DESC) AS newest
                FROM ops.batch WHERE status = 'transformed'
            ) b WHERE newest > %s
        ) old
        WHERE r.batch_id = old.batch_id
        """,
        (keep,),
    ).rowcount
