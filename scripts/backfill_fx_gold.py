"""Historical load of FX/gold rates (task 3.13).

Usage (needs internet + the database from docker compose):
    python scripts/backfill_fx_gold.py 2026-09-25 2026-10-25

For each day it calls the API for that date and stores the response in raw.
Days already stored are skipped, so you can run it again safely.
The World Bank connector needs no backfill: every response already holds all years.
NOTE: the first date the API has is not confirmed. Days that fail are listed at
the end; if old days always fail, that is simply where the history starts.
"""
import os
import sys
import time
from datetime import date, timedelta

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src.common.raw_store import _connect  # noqa: E402
from src.connectors.fx_gold import FxGoldConnector  # noqa: E402


def stored_endpoints():
    conn = _connect()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT endpoint FROM raw.api_responses WHERE source = 'fx_gold'")
            return {row[0] for row in cur.fetchall()}
    finally:
        conn.close()


def main(start, end):
    done = stored_endpoints()
    failed, saved = [], 0
    day = start
    while day <= end:
        connector = FxGoldConnector(date=day.isoformat())
        if FxGoldConnector.URLS[0].format(date=day.isoformat()) in done:
            print(day, "already stored, skipped")
        else:
            try:
                valid, rejected = connector.run(store=True)
                saved += 1
                print(day, f"saved ({len(valid)} valid, {len(rejected)} rejected)")
            except Exception as exc:  # keep going: one bad day must not stop the rest
                failed.append(day)
                print(day, "FAILED:", exc)
            time.sleep(0.5)  # be polite
        day += timedelta(days=1)
    print(f"\nDone: {saved} days saved, {len(failed)} failed: {[d.isoformat() for d in failed]}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: python scripts/backfill_fx_gold.py START_DATE END_DATE (YYYY-MM-DD)")
    main(date.fromisoformat(sys.argv[1]), date.fromisoformat(sys.argv[2]))
