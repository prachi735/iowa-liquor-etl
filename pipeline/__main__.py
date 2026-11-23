"""Command line: python -m pipeline <command>. Run with --help for the list."""
from __future__ import annotations

import argparse
import logging
import sys
from datetime import date
from pathlib import Path

import psycopg
from psycopg import sql

from . import config, db, ops
from .extract import download, unpack
from .load import load_file, prune_raw
from .transform import apply_rules, build_marts, global_checks, transform_all

log = logging.getLogger("pipeline")


def configure_logging(verbose: bool = False) -> None:
    level = logging.DEBUG if verbose else logging.INFO
    logger = logging.getLogger("pipeline")
    logger.setLevel(level)
    if not logger.handlers:
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)-7s %(message)s", "%H:%M:%S"))
        logger.addHandler(handler)
    logger.propagate = False


def cmd_setup(args) -> None:
    """Create the database if missing, then every schema, table, function and rule."""
    dbname = config.db_params()["dbname"]
    with db.connect("postgres") as admin:
        version = admin.execute("SHOW server_version_num").fetchone()[0]
        if int(version) < config.MIN_SERVER_VERSION:
            raise db.PipelineError(f"PostgreSQL 16 or later is required (server is {version}).")
        exists = admin.execute("SELECT 1 FROM pg_database WHERE datname = %s", (dbname,)).fetchone()
        if not exists:
            admin.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier(dbname)))
            log.info("   created database %s", dbname)
    with db.connect() as conn:
        with conn.transaction():
            for path in db.sql_files("00_setup"):
                db.run_sql_file(conn, path)
    log.info("   schemas ready in %s", dbname)


def collect_files(paths: list[str]) -> list[Path]:
    files: list[Path] = []
    for p in paths:
        files += unpack(Path(p))
    return files


def run_command(name: str, work) -> int:
    """Wrap a command in an ops.run row so every attempt, good or bad, is logged."""
    conn = db.connect()
    try:
        run_id = ops.start_run(conn, name)
        try:
            work(conn, run_id)
        except (db.PipelineError, psycopg.Error, OSError) as exc:
            ops.finish_run(conn, run_id, False, str(exc)[:2000])
            log.error("Run %s failed: %s", run_id, exc)
            return 1
        ops.finish_run(conn, run_id, True)
        log.info("Run %s succeeded.", run_id)
        return 0
    finally:
        conn.close()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="python -m pipeline", description=__doc__)
    parser.add_argument("-v", "--verbose", action="store_true", help="enable debug logging")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("setup", help="create the database objects (safe to re-run)")

    p = sub.add_parser("reset", help="drop all pipeline schemas and data, then run setup again")
    p.add_argument("--yes", action="store_true", help="confirm that all loaded data may be dropped")

    p = sub.add_parser("download", help="download a dataset into data/landing")
    p.add_argument("dataset", help="a year (2012-2026), past30, past90 or combined")

    p = sub.add_parser("load", help="load CSV or zip files into raw")
    p.add_argument("files", nargs="+")

    p = sub.add_parser("transform", help="transform loaded batches, run checks, rebuild marts")
    p.add_argument("--no-marts", action="store_true")

    p = sub.add_parser("run", help="monthly update: download, load, transform")
    p.add_argument("--dataset", default=config.MONTHLY_DATASET)
    p.add_argument("--file", help="use a file you downloaded instead of downloading")

    p = sub.add_parser("backfill", help="download, load and transform whole years, oldest first")
    p.add_argument("--from", dest="first", type=int, required=True)
    p.add_argument("--to", dest="last", type=int, default=date.today().year)

    sub.add_parser("check", help="run the global checks only")
    sub.add_parser("marts", help="rebuild the marts only")
    sub.add_parser("rules", help="re-apply the rule tables to the dimensions, then rebuild the marts")
    sub.add_parser("status", help="show recent runs, batches and failed checks")

    p = sub.add_parser("prune-raw", help="delete raw rows of old transformed batches")
    p.add_argument("--keep", type=int, default=config.RAW_KEEP_BATCHES)

    p = sub.add_parser("retry", help="mark a failed batch as loaded so transform picks it up again")
    p.add_argument("batch_id", type=int)

    args = parser.parse_args(argv)
    configure_logging(args.verbose)

    if args.command == "setup":
        try:
            cmd_setup(args)
        except (db.PipelineError, psycopg.Error) as exc:
            log.error("Setup failed: %s", exc)
            return 1
        return 0

    if args.command == "reset":
        if not args.yes:
            print("This drops every loaded row and the run log. Re-run with --yes to confirm.")
            return 1
        with db.connect() as conn:
            conn.execute("DROP SCHEMA IF EXISTS marts, core, staging, raw, ops CASCADE")
        log.info("   dropped schemas marts, core, staging, raw, ops")
        return main(["setup"])

    if args.command == "status":
        return show_status()

    def work(conn, run_id):
        if args.command == "download":
            with ops.step(conn, run_id, f"download {args.dataset}") as info:
                files = download(args.dataset)
                info.message = ", ".join(f.name for f in files)
        elif args.command == "load":
            for f in collect_files(args.files):
                load_file(conn, run_id, f)
        elif args.command == "transform":
            transform_all(conn, run_id, marts=not args.no_marts)
        elif args.command == "run":
            with ops.step(conn, run_id, f"get {args.file or args.dataset}") as info:
                files = collect_files([args.file]) if args.file else download(args.dataset)
                info.message = ", ".join(f.name for f in files)
            for f in files:
                load_file(conn, run_id, f, source=args.dataset if not args.file else None)
            transform_all(conn, run_id)
            with ops.step(conn, run_id, "prune raw") as info:
                info.rows = prune_raw(conn)
        elif args.command == "backfill":
            for year in range(args.first, args.last + 1):
                with ops.step(conn, run_id, f"download {year}") as info:
                    files = download(str(year))
                    info.message = ", ".join(f.name for f in files)
                for f in files:
                    load_file(conn, run_id, f, source=str(year))
                transform_all(conn, run_id, marts=(year == args.last))
        elif args.command == "check":
            global_checks(conn, run_id)
        elif args.command == "marts":
            build_marts(conn, run_id)
        elif args.command == "rules":
            apply_rules(conn, run_id)
            build_marts(conn, run_id)
        elif args.command == "prune-raw":
            with ops.step(conn, run_id, "prune raw") as info:
                info.rows = prune_raw(conn, args.keep)
        elif args.command == "retry":
            n = conn.execute(
                "UPDATE ops.batch SET status = 'loaded' WHERE batch_id = %s AND status = 'failed'",
                (args.batch_id,),
            ).rowcount
            log.info("   batch %s: %s", args.batch_id, "reset to loaded" if n else "not in failed state")

    raw_args = argv if argv is not None else sys.argv[1:]
    return run_command(" ".join(raw_args) or args.command, work)


def show_status() -> int:
    with db.connect() as conn:
        for title, sql in [
            ("Recent runs", "SELECT run_id, command, status, started_at::timestamp(0), "
             "finished_at - started_at AS took, left(message, 80) AS message "
             "FROM ops.run ORDER BY run_id DESC LIMIT 8"),
            ("Batches", "SELECT batch_id, file_name, status, rows_loaded, window_start, window_end "
             "FROM ops.batch ORDER BY batch_id DESC LIMIT 10"),
            ("Latest check results (failed rows > 0)", "SELECT run_id, batch_id, check_name, severity, "
             "failed_rows, left(detail, 70) AS detail FROM ops.check_result WHERE failed_rows > 0 "
             "AND run_id = (SELECT max(run_id) FROM ops.check_result) ORDER BY check_id"),
            ("Row counts", "SELECT 'fact_sales' AS tbl, count(*) FROM core.fact_sales UNION ALL "
             "SELECT 'invoices', count(*) FROM core.invoice WHERE deleted_batch_id IS NULL UNION ALL "
             "SELECT 'stores (versions)', count(*) FROM core.dim_store UNION ALL "
             "SELECT 'items (versions)', count(*) FROM core.dim_item"),
        ]:
            cols, rows = db.query(conn, sql)
            print(f"\n{title}")
            print("  " + " | ".join(cols))
            for r in rows:
                print("  " + " | ".join("" if v is None else str(v) for v in r))
    return 0


if __name__ == "__main__":
    sys.exit(main())
