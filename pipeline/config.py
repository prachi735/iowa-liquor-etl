"""Settings, read from environment variables or a .env file in the repo root."""
from __future__ import annotations

import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SQL_DIR = ROOT / "sql"

# Iowa Data Hub dataset ids (https://data.iowa.gov/catalog/dataset/<id>)
DATASETS: dict[str, int] = {
    "combined": 1051,   # Jan 2012 to the latest month, ~35M rows
    "past30": 1075,     # last 30 days reported
    "past90": 1078,     # last 90 days reported
    **{str(year): 1249 + (year - 2012) for year in range(2012, 2027)},  # one per year
}
DOWNLOAD_URL = "https://idh-be.iowa.gov/api/v1/datasets/{id}/rows.csv"

# The 23 columns the source publishes, in the documented order.
EXPECTED_COLUMNS = [
    "invoice_id", "ordered_on", "store_no", "store_name", "store_address", "store_city",
    "store_zip_code", "county_fips_code", "county_name", "category_code", "category_name",
    "vendor_number", "vendor_name", "item_no", "im_desc", "pack", "bottle_volume_ml",
    "state_bottle_cost", "state_bottle_retail", "sales_bottles", "sales_dollars",
    "sales_liters", "sales_gallons",
]

MIN_SERVER_VERSION = 160000  # PostgreSQL 16: pg_input_is_valid() is used in staging


def load_dotenv(path: Path = ROOT / ".env") -> None:
    """Minimal .env reader: KEY=VALUE lines; real environment variables win."""
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


load_dotenv()


def db_params(dbname: str | None = None) -> dict[str, str]:
    """Connection settings for psycopg; empty values are left to libpq defaults."""
    params = {
        "host": os.getenv("PGHOST", "localhost"),
        "port": os.getenv("PGPORT", "5432"),
        "dbname": dbname or os.getenv("PGDATABASE", "iowa_liquor"),
        "user": os.getenv("PGUSER", "postgres"),
        "password": os.getenv("PGPASSWORD", ""),
    }
    return {k: v for k, v in params.items() if v}


DATA_DIR = Path(os.getenv("IOWA_DATA_DIR", ROOT / "data"))
LANDING_DIR = DATA_DIR / "landing"
RAW_KEEP_BATCHES = int(os.getenv("RAW_KEEP_BATCHES", "2"))
MONTHLY_DATASET = os.getenv("MONTHLY_DATASET", "past30")
