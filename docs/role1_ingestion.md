# Role 1: APIs and official file (documentation)

## What it does
Three connectors collect data and save it untouched in `raw`; staging builders then clean it.

| Source | File | Raw table | Staging table |
|---|---|---|---|
| FX / gold | `src/connectors/fx_gold.py` | `raw.api_responses` | `staging.fx_gold_clean` |
| World Bank | `src/connectors/world_bank.py` | `raw.api_responses` | `staging.indicators_clean` |
| Official file | `src/connectors/official_file.py` | `raw.files` (+ file on the volume) | `staging.indicators_clean` (not built yet) |

## Flow of one run
`fetch()` (timeout, status check, JSON shape check) -> `raw_store` (save raw) -> `parse()` -> `validate()` (valid rows + rejected rows with a reason) -> staging builder.

## How Role 4 plugs it into a DAG
```python
from src.connectors.fx_gold import FxGoldConnector
from src.transform.api_staging import load_fx_gold_staging

valid, rejected = FxGoldConnector().run(store=True)   # fetch + save raw + parse + validate
# log `rejected` to ops.records_rejected with stage='validate' (ops_log.py)
load_fx_gold_staging()                                 # rebuild staging from raw
```
Same pattern for `WorldBankConnector` and `load_indicator_staging()`.
Schedules: FX/gold daily; World Bank and the official file weekly or monthly.

## Decisions
- Gold = international spot price converted to EGP per gram (24/21/18 karat). Not the jeweller's price.
- World Bank years without data are kept with `value = NULL`. Nothing is filled or invented.
- If the same day is collected twice, the latest collection wins in staging.
- `raw` is never deleted, so staging can always be rebuilt.

## Limits (be honest in the demo)
- Dollar/gold history length depends on the API (unconfirmed, see `docs/sources.md`).
- Correlation with the price index uses ~30 days only and is **not causation**.
- Source: fawazahmed0 currency API and the World Bank open data.

## Tests
`python -m pytest` runs parser, validation and staging tests on saved samples (no internet needed).
