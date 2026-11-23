"""Get source files into data/landing: download from the Iowa Data Hub, or unpack a file
downloaded by hand (zip or csv). Returns the CSV paths to load."""
from __future__ import annotations

import logging
import shutil
import urllib.request
import zipfile
from datetime import date
from pathlib import Path

from . import config
from .db import PipelineError

CHUNK = 1 << 20  # 1 MiB
log = logging.getLogger(__name__)


def download(dataset: str, dest_dir: Path | None = None) -> list[Path]:
    """Download one dataset (a year such as '2025', 'past30', 'past90' or 'combined')."""
    if dataset not in config.DATASETS:
        raise PipelineError(f"Unknown dataset '{dataset}'. Use one of: {', '.join(config.DATASETS)}")
    dest_dir = Path(dest_dir) if dest_dir is not None else config.LANDING_DIR
    url = config.DOWNLOAD_URL.format(id=config.DATASETS[dataset])
    dest_dir.mkdir(parents=True, exist_ok=True)
    stamp = date.today().isoformat()
    part = dest_dir / f"iowa_liquor_{dataset}_{stamp}.part"
    request = urllib.request.Request(url, headers={"User-Agent": "iowa-liquor-etl/1.0"})
    log.info("   downloading %s", url)
    try:
        with urllib.request.urlopen(request, timeout=300) as response, part.open("wb") as out:
            total = 0
            while chunk := response.read(CHUNK):
                out.write(chunk)
                total += len(chunk)
                if total % (50 * CHUNK) < CHUNK:
                    log.info("   %s MiB", f"{total / CHUNK:,.0f}")
    except OSError as exc:
        part.unlink(missing_ok=True)
        raise PipelineError(
            f"Download failed ({exc}). Download the file from https://data.iowa.gov/catalog/dataset/"
            f"{config.DATASETS[dataset]} instead and run: python -m pipeline load <file>"
        ) from exc
    return unpack(part, name=f"iowa_liquor_{dataset}_{stamp}")


def unpack(path: Path, name: str | None = None) -> list[Path]:
    """Turn a downloaded file (zip or csv, any extension) into one or more CSV files."""
    path = Path(path)
    if not path.exists():
        raise PipelineError(f"File not found: {path}")
    name = name or path.stem
    if zipfile.is_zipfile(path):
        out_dir = config.LANDING_DIR / name
        out_dir.mkdir(parents=True, exist_ok=True)
        csvs = []
        with zipfile.ZipFile(path) as zf:
            for member in zf.infolist():
                if member.is_dir() or not member.filename.lower().endswith(".csv"):
                    continue
                target = out_dir / Path(member.filename).name
                if not target.exists() or target.stat().st_size != member.file_size:
                    with zf.open(member) as src, target.open("wb") as dst:
                        shutil.copyfileobj(src, dst, CHUNK)
                csvs.append(target)
        if path.suffix == ".part":
            path.unlink()
        if not csvs:
            raise PipelineError(f"No CSV files inside {path.name}")
        return sorted(csvs)
    if path.suffix == ".part":
        final = path.with_suffix(".csv")
        path.replace(final)
        return [final]
    return [path]
