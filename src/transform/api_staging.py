"""Staging builders for the API sources (tasks 4.9 and 4.10).

raw.api_responses  --(parse + validate)-->  staging.fx_gold_clean / staging.indicators_clean

The staging tables are REBUILT on every run (see sql/30_staging.sql): we delete
this source's rows and insert them again from ALL raw payloads. Because raw is
never deleted, the result is the same however many times it runs (idempotent).

Pure functions (build_*) need no database and are unit tested.
load_* functions talk to Postgres through the same connection as raw_store.
"""
from datetime import datetime

from src.connectors.fx_gold import FxGoldConnector
from src.connectors.world_bank import WorldBankConnector

# Names / units for indicators we know. Unknown codes fall back to the code itself.
INDICATOR_META = {
    "FP.CPI.TOTL.ZG": ("Inflation, consumer prices (annual %)", "%"),
}


def split_period(period):
    """'2023' -> (2023, None); '2026-08' -> (2026, 8); anything else -> None."""
    p = str(period).strip()
    try:
        if len(p) == 4 and p.isdigit():
            return int(p), None
        if len(p) == 7 and p[4] == "-":
            year, month = int(p[:4]), int(p[5:])
            if 1 <= month <= 12:
                return year, month
    except ValueError:
        pass
    return None


def build_fx_gold_staging(payloads):
    """payloads: list of (raw_json, collected_at). Returns staging.fx_gold_clean rows.

    If the same rate/day was collected twice, the LATEST collection wins.
    """
    connector = FxGoldConnector()
    best = {}
    for raw, collected_at in sorted(payloads, key=lambda x: x[1]):
        try:
            valid, _rejected = connector.validate(connector.parse(raw))
        except ValueError:
            continue  # unreadable payload: already logged when it was collected
        for r in valid:
            rate_date = datetime.fromisoformat(r["observed_at"]).date()
            best[(r["code"], r["karat"], rate_date)] = {
                "source": r["source"], "code": r["code"], "kind": r["kind"],
                "karat": r["karat"], "rate": r["rate"],
                "rate_date": rate_date, "observed_at": r["observed_at"],
            }
    return sorted(best.values(), key=lambda r: (r["rate_date"], r["code"], r["karat"] or 0))


def build_indicator_staging(payloads):
    """World Bank payloads -> staging.indicators_clean rows.

    Task 4.10 (missing values): a year with value=None is KEPT with value NULL.
    We never invent or fill a number. dwh.fact_indicator allows NULL on purpose,
    so the gap stays visible in the data instead of silently disappearing.
    """
    connector = WorldBankConnector()
    best = {}
    for raw, collected_at in sorted(payloads, key=lambda x: x[1]):
        try:
            valid, _rejected = connector.validate(connector.parse(raw))
        except ValueError:
            continue
        for r in valid:
            parts = split_period(r["period"])
            if parts is None:
                continue
            year, month = parts
            name, unit = INDICATOR_META.get(r["indicator_code"], (r["indicator_code"], None))
            best[(r["indicator_code"], r["country"], year, month)] = {
                "source": r["source"], "indicator_code": r["indicator_code"],
                "indicator_name": name, "unit": unit,
                "frequency": "annual" if month is None else "monthly",
                "country": r["country"], "period_year": year, "period_month": month,
                "value": r["value"],
            }
    return sorted(best.values(),
                  key=lambda r: (r["indicator_code"], r["country"], r["period_year"],
                                 r["period_month"] or 0))


# ----------------------------------------------------------- database part
def _read_payloads(cur, source):
    cur.execute(
        "SELECT payload, collected_at FROM raw.api_responses "
        "WHERE source = %s AND payload IS NOT NULL ORDER BY collected_at", (source,))
    return cur.fetchall()


def load_fx_gold_staging():
    """Rebuild staging.fx_gold_clean from raw. Returns the number of rows written."""
    from psycopg2.extras import execute_values
    from src.common.raw_store import _connect

    conn = _connect()
    try:
        with conn:  # one transaction: delete + insert together or not at all
            with conn.cursor() as cur:
                rows = build_fx_gold_staging(_read_payloads(cur, "fx_gold"))
                cur.execute("DELETE FROM staging.fx_gold_clean WHERE source = 'fx_gold'")
                if rows:
                    execute_values(
                        cur,
                        "INSERT INTO staging.fx_gold_clean "
                        "(source, code, kind, karat, rate, rate_date, observed_at) VALUES %s",
                        [(r["source"], r["code"], r["kind"], r["karat"], r["rate"],
                          r["rate_date"], r["observed_at"]) for r in rows])
                return len(rows)
    finally:
        conn.close()


def load_indicator_staging():
    """Rebuild this source's rows in staging.indicators_clean. Returns rows written."""
    from psycopg2.extras import execute_values
    from src.common.raw_store import _connect

    conn = _connect()
    try:
        with conn:
            with conn.cursor() as cur:
                rows = build_indicator_staging(_read_payloads(cur, "world_bank"))
                cur.execute("DELETE FROM staging.indicators_clean WHERE source = 'world_bank'")
                if rows:
                    execute_values(
                        cur,
                        "INSERT INTO staging.indicators_clean "
                        "(source, indicator_code, indicator_name, unit, frequency, country, "
                        "period_year, period_month, value) VALUES %s",
                        [(r["source"], r["indicator_code"], r["indicator_name"], r["unit"],
                          r["frequency"], r["country"], r["period_year"], r["period_month"],
                          r["value"]) for r in rows])
                return len(rows)
    finally:
        conn.close()
