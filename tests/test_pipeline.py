"""Tests. The unit tests need nothing; the integration test needs a PostgreSQL 16+ server and
uses a separate database whose name must end in _test (default iowa_liquor_test).
It drops and rebuilds the pipeline schemas in that database."""
from __future__ import annotations

import csv
import os
import random
import zipfile
from pathlib import Path

import pytest

from pipeline import config
from pipeline.extract import unpack
from pipeline.load import SchemaDriftError, check_header, read_header, sha256

FIXTURE = Path(__file__).parent / "fixtures" / "sample_orders.csv"
TEST_DB = os.getenv("PGDATABASE_TEST", "iowa_liquor_test")


# ---------- unit tests -------------------------------------------------------------

def test_fixture_header_matches_expected_columns():
    check_header(read_header(FIXTURE))


def test_header_drift_is_rejected():
    header = list(config.EXPECTED_COLUMNS)
    header[5] = "store_town"
    with pytest.raises(SchemaDriftError, match="store_town"):
        check_header(header)


def test_reordered_columns_are_accepted():
    check_header(list(reversed(config.EXPECTED_COLUMNS)))


def test_unpack_zip(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "LANDING_DIR", tmp_path / "landing")
    archive = tmp_path / "download.zip"
    with zipfile.ZipFile(archive, "w") as zf:
        zf.write(FIXTURE, "rows.csv")
    files = unpack(archive)
    assert [f.name for f in files] == ["rows.csv"]
    assert sha256(files[0]) == sha256(FIXTURE)


# ---------- integration test ------------------------------------------------------

def read_rows(path: Path) -> list[dict]:
    with path.open(encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def write_rows(path: Path, rows: list[dict]) -> Path:
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=config.EXPECTED_COLUMNS)
        writer.writeheader()
        writer.writerows(rows)
    return path


@pytest.fixture(scope="module")
def db(tmp_path_factory):
    psycopg = pytest.importorskip("psycopg")
    from psycopg import sql

    assert TEST_DB.endswith("_test"), "the test database name must end in _test"
    os.environ["PGDATABASE"] = TEST_DB
    from pipeline import db as dbmod
    from pipeline.__main__ import main
    try:
        with dbmod.connect("postgres") as admin:
            if not admin.execute("SELECT 1 FROM pg_database WHERE datname = %s", (TEST_DB,)).fetchone():
                admin.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier(TEST_DB)))
    except psycopg.Error as exc:
        pytest.skip(f"PostgreSQL not reachable: {exc}")
    with dbmod.connect() as conn:
        conn.execute("DROP SCHEMA IF EXISTS marts, core, staging, raw, ops CASCADE")
    assert main(["setup"]) == 0
    conn = dbmod.connect()
    yield conn, main, tmp_path_factory.mktemp("files")
    conn.close()


def scalar(conn, sql, params=None):
    return conn.execute(sql, params).fetchone()[0]


def test_full_cycle(db):
    conn, main, tmp = db
    rows = read_rows(FIXTURE)
    file_dollars = round(sum(float(r["sales_dollars"]) for r in rows), 2)

    # 1. First load: every invoice is new, every line lands, renamed store has 2 versions.
    assert main(["load", str(FIXTURE)]) == 0
    assert main(["transform"]) == 0
    assert scalar(conn, "SELECT command FROM ops.run ORDER BY run_id DESC LIMIT 1") == "transform"
    assert scalar(conn, "SELECT count(*) FROM core.fact_sales") == len(rows)
    assert float(scalar(conn, "SELECT sum(dollars) FROM core.fact_sales")) == file_dollars
    assert scalar(conn, "SELECT count(*) FROM core.dim_store WHERE store_no = '4042'") == 2
    assert scalar(conn, "SELECT count(*) FROM core.fact_sales WHERE is_return") > 0

    # 2. Same file again: skipped by hash, nothing changes.
    batches = scalar(conn, "SELECT count(*) FROM ops.batch")
    assert main(["load", str(FIXTURE)]) == 0
    assert scalar(conn, "SELECT count(*) FROM ops.batch") == batches

    # 3. A later pull of the same period with real-world edits.
    invoices = sorted({r["invoice_id"] for r in rows if r["invoice_id"].startswith("INV-")})
    changed_inv, deleted_inv, template_inv = invoices[0], invoices[1], invoices[2]
    edited = []
    for r in rows:
        r = dict(r)
        if r["invoice_id"] == deleted_inv:
            continue
        if r["invoice_id"] == changed_inv and not any(e["invoice_id"] == changed_inv for e in edited):
            price = float(r["sales_dollars"]) / int(r["sales_bottles"])
            r["sales_bottles"] = str(int(r["sales_bottles"]) + 1)
            r["sales_dollars"] = f"{float(r['sales_dollars']) + price:.2f}"
        if "." not in r["sales_dollars"]:
            r["sales_dollars"] += ".00"  # formatting change only: must not count as a change
        edited.append(r)
    edited += [dict(r, invoice_id="INV-9999999") for r in rows if r["invoice_id"] == template_inv]
    store = "4042"
    rename_from = "2026-10-20"
    for r in edited:
        if r["store_no"] == store and r["ordered_on"] >= rename_from:
            r["store_name"] = "LAKE OHANA MARKET / GLENWOOD NORTH"
    random.Random(1).shuffle(edited)
    later = write_rows(tmp / "later_pull.csv", edited)

    assert main(["load", str(later)]) == 0
    assert main(["transform"]) == 0
    batch = scalar(conn, "SELECT max(batch_id) FROM ops.batch")
    counts = conn.execute(
        """SELECT count(*) FILTER (WHERE first_batch_id = %(b)s),
                  count(*) FILTER (WHERE changed_batch_id = %(b)s),
                  count(*) FILTER (WHERE deleted_batch_id = %(b)s)
           FROM core.invoice""", {"b": batch}).fetchone()
    assert counts == (1, 1, 1)  # new, changed, deleted
    later_dollars = round(sum(float(r["sales_dollars"]) for r in edited), 2)
    assert float(scalar(conn, "SELECT sum(dollars) FROM core.fact_sales")) == later_dollars
    # The rename created a third version, and older fact rows moved to it.
    assert scalar(conn, "SELECT count(*) FROM core.dim_store WHERE store_no = %s", (store,)) == 3
    assert scalar(conn, """
        SELECT count(*) FROM core.fact_sales f JOIN core.dim_store d ON d.store_sk = f.store_sk
        WHERE f.store_no = %s AND f.ordered_on >= %s AND d.store_name <> 'LAKE OHANA MARKET / GLENWOOD NORTH'
        """, (store, rename_from)) == 0

    # 4. A truncated download (40% of invoices missing) is stopped and rolled back.
    keep = set(random.Random(2).sample(invoices, int(len(invoices) * 0.6)))
    truncated = write_rows(tmp / "truncated.csv", [r for r in edited if r["invoice_id"] in keep])
    assert main(["load", str(truncated)]) == 0
    assert main(["transform"]) == 1
    assert scalar(conn, "SELECT status FROM ops.batch ORDER BY batch_id DESC LIMIT 1") == "failed"
    assert float(scalar(conn, "SELECT sum(dollars) FROM core.fact_sales")) == later_dollars

    # 5. An invoice number reused a year earlier is stopped instead of overwriting history.
    reused = [dict(r, ordered_on="2025-10-15") for r in edited if r["invoice_id"] == template_inv]
    assert main(["load", str(write_rows(tmp / "reused_id.csv", reused))]) == 0
    assert main(["transform"]) == 1
    assert scalar(conn, "SELECT ordered_on::text FROM core.invoice WHERE invoice_id = %s",
                  (template_inv,)) != "2025-10-15"

    # 6. Marts agree with the fact table and survive rebuilds with dependent BI views attached.
    assert float(scalar(conn, "SELECT sum(dollars) FROM marts.monthly_kpis")) == later_dollars
    assert float(scalar(conn, "SELECT sum(dollars) FROM marts.category_month")) == later_dollars
    conn.execute("CREATE OR REPLACE VIEW marts.v_test_kpi AS SELECT month, dollars FROM marts.monthly_kpis")
    try:
        assert main(["marts"]) == 0
        assert float(scalar(conn, "SELECT sum(dollars) FROM marts.v_test_kpi")) == later_dollars
    finally:
        conn.execute("DROP VIEW IF EXISTS marts.v_test_kpi")


def test_setup_preserves_custom_rule_edits(db):
    conn, main, _ = db
    conn.execute(
        "UPDATE core.category_group_rule SET category_group = 'Custom Vodka' WHERE code_prefix = '1031'"
    )
    try:
        assert main(["setup"]) == 0
        assert scalar(
            conn, "SELECT category_group FROM core.category_group_rule WHERE code_prefix = '1031'"
        ) == "Custom Vodka"
    finally:
        conn.execute(
            "UPDATE core.category_group_rule SET category_group = 'Vodka' WHERE code_prefix = '1031'"
        )


def test_product_line_rule(db):
    conn, _, _ = db
    cases = {
        "TITOS HANDMADE VODKA MINI 4 PACK": "TITOS HANDMADE VODKA",
        "GREY GOOSE MINI 4PK": "GREY GOOSE",
        "SEAGRAMS 7 CROWN PET FLASK": "SEAGRAMS 7 CROWN",
        "FIREBALL CINNAMON WHISKEY 100ML CARRIER": "FIREBALL CINNAMON WHISKEY",
        "SOOH MILLET ARMAGNAC VS": "MILLET ARMAGNAC VS",
        "CAPTAIN MORGAN ORIGINAL W/ 2 SHOT GLASSES PET": "CAPTAIN MORGAN ORIGINAL",
        "GOTCHA VODKA": "GOTCHA VODKA",
    }
    for raw, expected in cases.items():
        assert scalar(conn, "SELECT staging.product_line(%s)", (raw,)) == expected, raw
    cleaned = scalar(conn, "SELECT staging.item_desc('DISARONNO AMARETTO USE CODE 64238')")
    assert cleaned == "DISARONNO AMARETTO"
    assert scalar(conn, "SELECT staging.clean_key('010017')") == "10017"
    assert scalar(conn, "SELECT staging.clean_key('65.0')") == "65"
