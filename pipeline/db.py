"""Database helpers: one autocommit connection; work runs inside explicit transactions."""
from __future__ import annotations

from pathlib import Path

import psycopg

from . import config


class PipelineError(RuntimeError):
    """A failure the run log should record with a readable message."""


def connect(dbname: str | None = None) -> psycopg.Connection:
    return psycopg.connect(autocommit=True, **config.db_params(dbname))


def sql_files(folder: str) -> list[Path]:
    files = sorted((config.SQL_DIR / folder).glob("*.sql"))
    if not files:
        raise PipelineError(f"No SQL files found in sql/{folder}")
    return files


def run_sql_file(conn: psycopg.Connection, path: Path) -> None:
    """Run a whole SQL file (several statements, no parameters)."""
    try:
        conn.execute(path.read_text(encoding="utf-8"))
    except psycopg.Error as exc:
        raise PipelineError(f"{path.relative_to(config.ROOT)}: {exc}") from exc


def query(conn: psycopg.Connection, sql: str, params=None) -> tuple[list[str], list[tuple]]:
    cur = conn.execute(sql, params)
    columns = [c.name for c in cur.description] if cur.description else []
    return columns, cur.fetchall()


def set_batch(conn: psycopg.Connection, batch_id: int) -> None:
    """Expose the batch id to SQL files as current_setting('pipeline.batch_id')."""
    conn.execute("SELECT set_config('pipeline.batch_id', %s, true)", (str(batch_id),))
