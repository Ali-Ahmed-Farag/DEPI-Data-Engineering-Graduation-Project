"""Run this on YOUR computer (needs internet) to save REAL samples:  python scripts/fetch_samples.py

Covers checklist tasks 1.13 and 1.14 and replaces the placeholder sample files.
It also answers task 1.12: it prints whether EGP and XAU are really in the response.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src.connectors.fx_gold import FxGoldConnector  # noqa: E402
from src.connectors.world_bank import WorldBankConnector  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tests", "samples")


def save(name, data):
    path = os.path.join(OUT, name)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print("saved", path)


wb = WorldBankConnector()
wb_raw = wb.fetch()
save("world_bank_egy_inflation.json", wb_raw)
valid, rejected = wb.validate(wb.parse(wb_raw))
print(f"World Bank: {len(valid)} valid rows, {len(rejected)} rejected, "
      f"{sum(r['value'] is None for r in valid)} gaps (null values)")

fx = FxGoldConnector()
fx_raw = fx.fetch()
save("fx_gold_usd_latest.json", fx_raw)
print("FX/Gold date:", fx_raw["date"], "| has EGP:", "egp" in fx_raw["usd"],
      "| has XAU:", "xau" in fx_raw["usd"], "| currencies in file:", len(fx_raw["usd"]))
valid, rejected = fx.validate(fx.parse(fx_raw))
for r in valid:
    print(f"  {r['code']:4} {str(r['karat'] or ''):>3}  {r['rate']:.2f} EGP")
print(f"FX/Gold: {len(valid)} valid, {len(rejected)} rejected")
