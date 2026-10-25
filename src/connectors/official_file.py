"""Official statistics file connector (CSV / Excel).  Tasks 5.1 - 5.3.

SKELETON: task 1.16 must first decide WHICH file (CAPMAS headline CPI or CBE
core inflation are the candidates, see docs/sources.md). Then fill in the
three settings below. Everything else (download, save on the volume, sha256,
register in raw.files, read with fixed columns) already works.

Settings (env vars win over the defaults):
  OFFICIAL_FILE_URL   direct download link of the file
  RAW_FILES_DIR       folder on the docker volume (default: data/raw_files)
  COLUMN_MAP          {exact header in the file: 'period' | 'value'}
"""
import hashlib
import os

import requests

from .base import BaseConnector, reject, is_number

REQUIRED = ("source", "indicator_code", "country", "period", "value")


def normalize_header(text):
    """Trim spaces and unify Arabic letter variants so header matching is stable."""
    text = " ".join(str(text).split())
    for a, b in (("أ", "ا"), ("إ", "ا"), ("آ", "ا"), ("ى", "ي"), ("ـ", "")):
        text = text.replace(a, b)
    return text


class OfficialFileConnector(BaseConnector):
    name = "official_file"
    HEADERS = {"User-Agent": "EcoPlatformBot/1.0 (student project)"}

    # ---- fill these in after task 1.16 ---------------------------------
    URL = os.getenv("OFFICIAL_FILE_URL")
    INDICATOR_CODE = "CPI_URBAN_ANNUAL"   # our own code for this series
    COUNTRY = "EGY"
    COLUMN_MAP = {}                       # e.g. {"الشهر": "period", "معدل التضخم": "value"}
    SHEET = 0                             # Excel sheet index or name
    # --------------------------------------------------------------------

    def __init__(self, url=None, save_dir=None, session=None):
        self.url = url or self.URL
        self.save_dir = save_dir or os.getenv("RAW_FILES_DIR", "data/raw_files")
        self.session = session or requests
        self.last_file = None

    def fetch(self):
        if not self.url:
            raise RuntimeError("Set OFFICIAL_FILE_URL (task 1.16: choose the file first)")
        resp = self.session.get(self.url, headers=self.HEADERS, timeout=60)
        self.last_endpoint = self.url
        self.last_status = resp.status_code
        resp.raise_for_status()
        content = resp.content
        os.makedirs(self.save_dir, exist_ok=True)
        file_name = os.path.basename(self.url.split("?")[0]) or "official_file.bin"
        path = os.path.join(self.save_dir, file_name)
        with open(path, "wb") as f:
            f.write(content)  # saved exactly as downloaded
        self.last_file = {
            "file_name": file_name,
            "file_path": path,
            "sha256": hashlib.sha256(content).hexdigest(),
            "size_bytes": len(content),
        }
        return self.last_file

    def store_raw(self, raw):
        from src.common import raw_store

        return raw_store.store_file(self.name, raw["file_name"], raw["file_path"],
                                    raw["sha256"], raw["size_bytes"])

    def parse(self, raw):
        import pandas as pd

        if not self.COLUMN_MAP:
            raise RuntimeError("COLUMN_MAP is empty: set it after looking at the file")
        path = raw["file_path"]
        if path.lower().endswith((".xlsx", ".xls")):
            df = pd.read_excel(path, sheet_name=self.SHEET)
        else:
            df = pd.read_csv(path)
        df.columns = [normalize_header(c) for c in df.columns]
        wanted = {normalize_header(k): v for k, v in self.COLUMN_MAP.items()}
        missing = [k for k in wanted if k not in df.columns]
        if missing:  # the file format changed: fail loudly instead of guessing
            raise ValueError(f"Official file: expected columns not found: {missing}")
        df = df[list(wanted)].rename(columns=wanted)
        rows = []
        for rec in df.to_dict("records"):
            value = rec["value"]
            if value != value:  # NaN -> None
                value = None
            rows.append({"source": self.name, "indicator_code": self.INDICATOR_CODE,
                         "country": self.COUNTRY, "period": str(rec["period"]).strip(),
                         "value": value})
        return rows

    def validate(self, rows):
        valid, rejected = [], []
        for r in rows:
            missing = [k for k in REQUIRED if k not in r]
            if missing:
                rejected.append(reject(r, f"missing field(s): {', '.join(missing)}"))
            elif not r["period"] or r["period"] == "nan":
                rejected.append(reject(r, "empty period"))
            elif r["value"] is not None and not is_number(r["value"]):
                rejected.append(reject(r, f"value is not a number: {r['value']!r}"))
            else:
                valid.append(r)
        return valid, rejected
