import json
import math
import os

from src.connectors.fx_gold import FxGoldConnector, GRAMS_PER_TROY_OUNCE

SAMPLE = os.path.join(os.path.dirname(__file__), "samples", "fx_gold_usd_latest.json")


def load():
    with open(SAMPLE, encoding="utf-8") as f:
        return json.load(f)


def by_key(rows):
    return {(r["code"], r["karat"]): r for r in rows}


def test_exact_math():
    raw = {"date": "2026-10-25", "usd": {"egp": 50.0, "eur": 0.5, "xau": 0.0004}}
    rows = by_key(FxGoldConnector().parse(raw))
    assert math.isclose(rows[("USD", None)]["rate"], 50.0)
    assert math.isclose(rows[("EUR", None)]["rate"], 100.0)  # 50 EGP/USD / 0.5 EUR/USD
    # 1 USD buys 0.0004 oz -> 1 oz = 2500 USD = 125000 EGP -> per gram:
    g24 = 125000 / GRAMS_PER_TROY_OUNCE
    assert math.isclose(rows[("XAU", 24)]["rate"], g24)
    assert math.isclose(rows[("XAU", 21)]["rate"], g24 * 21 / 24)
    assert math.isclose(rows[("XAU", 18)]["rate"], g24 * 18 / 24)


def test_sample_parse_and_validate():
    c = FxGoldConnector()
    rows = c.parse(load())
    assert {r["kind"] for r in rows} == {"currency", "gold"}
    for r in rows:
        assert set(r) == {"source", "code", "kind", "karat", "rate", "observed_at"}
        assert r["source"] == "fx_gold"
        assert r["observed_at"].startswith("2026-10-25")
    valid, rejected = c.validate(rows)
    assert len(valid) == len(rows) and not rejected
    k = by_key(valid)
    assert k[("XAU", 24)]["rate"] > k[("XAU", 21)]["rate"] > k[("XAU", 18)]["rate"]


def test_missing_currency_is_rejected_not_crashed():
    raw = {"date": "2026-10-25", "usd": {"egp": 50.0, "xau": 0.0004}}  # no eur/gbp/sar
    c = FxGoldConnector()
    valid, rejected = c.validate(c.parse(raw))
    assert {r["record"]["code"] for r in rejected} == {"EUR", "GBP", "SAR"}
    assert any(r["code"] == "USD" for r in valid)
    assert sum(r["code"] == "XAU" for r in valid) == 3


def test_validate_rules():
    c = FxGoldConnector()
    base = {"source": "fx_gold", "code": "USD", "kind": "currency", "karat": None,
            "rate": 48.0, "observed_at": "2026-10-25T00:00:00+03:00"}
    bad = [
        dict(base, rate=0),
        dict(base, rate=-1),
        dict(base, rate="48"),
        dict(base, rate=float("nan")),
        dict(base, kind="crypto"),
        dict(base, kind="gold", karat=22),
        dict(base, karat=21),
        {"source": "fx_gold"},
    ]
    valid, rejected = c.validate([base] + bad)
    assert valid == [base]
    assert len(rejected) == len(bad)


def test_shape_check_requires_egp():
    for bad in (None, {}, {"date": "2026-10-25", "usd": {"eur": 1}}, {"usd": {"egp": 1}}):
        try:
            FxGoldConnector._check_shape(bad)
        except ValueError:
            continue
        raise AssertionError(f"no error for {bad!r}")
