# Data sources (Role 1)

> Task 1.17. Role 2 adds the static shopping site section at the bottom.
> Items marked **VERIFY** were not confirmed by running code yet: run
> `python scripts/fetch_samples.py` and fix the text if reality differs.

## 1. FX and gold: fawazahmed0 currency API

| Item | Value |
|---|---|
| Type | REST API, JSON, no API key |
| URL | `https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@{date}/v1/currencies/usd.json` (`{date}` = `latest` or `YYYY-MM-DD`) |
| Fallback | `https://{date}.currency-api.pages.dev/v1/currencies/usd.json` |
| Data | 200+ currencies and metals, daily, USD as base |
| EGP support | **VERIFY**: the connector refuses a response without `egp`; `fetch_samples.py` prints it |
| Gold | `xau` = troy ounces per 1 USD. We derive EGP per gram: `egp / xau / 31.1035`, then x karat/24 for 24/21/18 |
| Rate limits | The project's wiki states no rate limits. We call it once a day. |
| Terms | Listed as CC0 (public domain) on a third-party index; **VERIFY** on the GitHub repo `fawazahmed0/exchange-api` |
| History | Date-based URLs; the earliest date available is **VERIFY** (needed for task 3.13) |
| Limitation | Gold is the international spot price converted to EGP. It is NOT the jeweller's price in Egypt. |
| Sample | `tests/samples/fx_gold_usd_latest.json` |
| Fallback plan | If EGP/XAU is missing or the API disappears: switch to another API with the same output shape. Only `fx_gold.py` changes. |

## 2. World Bank API

| Item | Value |
|---|---|
| Type | REST API, JSON, no key |
| URL | `https://api.worldbank.org/v2/country/EGY/indicator/FP.CPI.TOTL.ZG?format=json&per_page=500` |
| Data | Egypt, Inflation, consumer prices (annual %), one value per year |
| Gaps | Some years have `value: null`. Kept as NULL; staging decides (task 4.10). |
| Frequency | Annual, so we collect it monthly or less |
| Rate limits | No key; we make one call per run |
| Terms | World Bank open data terms, commonly CC BY 4.0: **VERIFY** and cite the World Bank in the demo |
| Sample | `tests/samples/world_bank_egy_inflation.json` |

## 3. Official file (CSV / Excel): NOT CHOSEN YET (task 1.16)

Candidates (a person must open the sites and pick a stable download link):

| Candidate | Publisher | Notes |
|---|---|---|
| Headline urban CPI | CAPMAS (Central Agency for Public Mobilization and Statistics) | Headline inflation is published by CAPMAS, often as PDF; look for an Excel/CSV table |
| Core inflation | Central Bank of Egypt (CBE) | Core inflation is calculated and published by the CBE |

To finish this section write: publisher, direct URL, format, update frequency, column headers (Arabic or English), whether reuse is allowed. Then set `OFFICIAL_FILE_URL` and `COLUMN_MAP` in `src/connectors/official_file.py`.
If no stable file download exists, tell the team early and switch to another official file (the guide allows replacing a source).

## 4. Static shopping site (Role 2)
_To be added by Role 2._
