import json
import os
from datetime import date, datetime

from src.transform.api_staging import (
    build_fx_gold_staging, build_indicator_staging, split_period)

HERE = os.path.dirname(__file__)


def load(name):
    with open(os.path.join(HERE, "samples", name), encoding="utf-8") as f:
        return json.load(f)


def test_split_period():
    assert split_period("2023") == (2023, None)
    assert split_period("2026-08") == (2026, 8)
    assert split_period(" 2026-08 ") == (2026, 8)
    for bad in ("23", "2026-13", "2026-00", "abcd", "", None, "2026/08"):
        assert split_period(bad) is None


def test_fx_gold_staging_columns_and_date():
    rows = build_fx_gold_staging([(load("fx_gold_usd_latest.json"), datetime(2026, 10, 25, 6))])
    assert rows
    for r in rows:
        assert set(r) == {"source", "code", "kind", "karat", "rate", "rate_date", "observed_at"}
        assert r["rate_date"] == date(2026, 10, 25)
    assert {(r["code"], r["karat"]) for r in rows} >= {("USD", None), ("XAU", 21)}


def test_fx_gold_staging_latest_collection_wins():
    old = {"date": "2026-10-25", "usd": {"egp": 40.0, "xau": 0.0004}}
    new = {"date": "2026-10-25", "usd": {"egp": 50.0, "xau": 0.0004}}
    rows = build_fx_gold_staging([(new, datetime(2026, 10, 25, 9)),
                                  (old, datetime(2026, 10, 25, 6))])  # order must not matter
    usd = [r for r in rows if r["code"] == "USD"]
    assert len(usd) == 1 and usd[0]["rate"] == 50.0


def test_fx_gold_staging_skips_unreadable_payload():
    good = load("fx_gold_usd_latest.json")
    rows = build_fx_gold_staging([({"oops": 1}, datetime(2026, 10, 24)),
                                  (good, datetime(2026, 10, 25))])
    assert rows  # the bad payload did not break the build


def test_indicator_staging_keeps_gaps_as_null():
    rows = build_indicator_staging([(load("world_bank_egy_inflation.json"), datetime(2026, 10, 25))])
    assert rows
    for r in rows:
        assert r["frequency"] == "annual" and r["period_month"] is None
        assert isinstance(r["period_year"], int)
        assert r["indicator_name"] and r["country"] == "EGY"
    assert any(r["value"] is None for r in rows)       # gap kept, not dropped or filled
    assert any(r["value"] is not None for r in rows)


def test_indicator_staging_dedupes_by_year():
    raw = load("world_bank_egy_inflation.json")
    rows = build_indicator_staging([(raw, datetime(2026, 10, 24)), (raw, datetime(2026, 10, 25))])
    years = [r["period_year"] for r in rows]
    assert len(years) == len(set(years))
