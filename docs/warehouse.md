# Warehouse (PostgreSQL) - R3

Everything lives in one PostgreSQL 16 server with two databases: `eco` (our data) and `airflow` (Airflow metadata). Inside `eco` data moves `raw -> staging -> dwh -> serving`, and `ops` holds monitoring tables. The star schema is drawn in [erd/warehouse_erd.md](erd/warehouse_erd.md).

## Schemas and who can touch what

| Schema | Content | Written by | Read by |
|---|---|---|---|
| `raw` | api_responses, html_pages, files (source data as collected) | connectors via `raw_store.py` | etl_user |
| `staging` | products, prices_clean, fx_gold_clean, indicators_clean | transform step | etl_user |
| `dwh` | dim_date, dim_source, dim_product (SCD2), dim_currency, dim_indicator, fact_price, fact_gold_fx, fact_indicator | load SQL in `sql/load/` | etl_user |
| `ops` | pipeline_runs, records_rejected, quality_results | `ops_log.py` | etl_user |
| `serving` | views only | created by `sql/60_serving.sql` and `sql/65_serving_fx_gold.sql` | **reader** (API and Grafana) |

- `etl_user` owns every schema and writes to raw/staging/dwh/ops. `reader` has SELECT on `serving` only; it cannot see the other schemas. Views run with their owner's rights, so a serving view can read `dwh` / `ops` for `reader`.
- The admin user (`POSTGRES_USER`, see `.env`) is only used to run the `sql/*.sql` files at first start.

## How the database is created

On the FIRST start with an empty `pgdata` volume, `docker/postgres/init/02_run_sql.sh` runs every top-level `sql/*.sql` in name order (00 roles, 10 schemas, 20 raw, 30 staging, 40 dwh, 50 ops, 60 and 65 serving). Role passwords come from `.env` (`ETL_USER_PASSWORD`, `READER_PASSWORD`). Init scripts do NOT run again on an existing volume: use `docker compose down -v` to start clean.

The sub-folders `sql/load/` and `sql/tests/` are not run at start, on purpose.

## Loading the warehouse (for Airflow, task `load`)

One file per source, each file is ONE transaction (dimensions first, then facts):

| File | Source | Reads | Writes |
|---|---|---|---|
| `sql/load/load_prices.sql` | static_site | staging.products, staging.prices_clean | dim_product (SCD2), fact_price |
| `sql/load/load_fx_gold.sql` | fx_gold | staging.fx_gold_clean | dim_currency, fact_gold_fx |
| `sql/load/load_indicators.sql` | world_bank, official_file | staging.indicators_clean | dim_indicator, fact_indicator |

Run them after the quality gate passed. They are safe to run again (idempotent): facts are UPSERTed on their primary key and the SCD2 only closes rows whose attributes changed.

From Python, run the whole file text in one `execute`. Two ways work (both tested):

    sql = open("sql/load/load_prices.sql", encoding="utf-8").read()

    # A) autocommit: the file's own BEGIN/COMMIT control the transaction
    conn.autocommit = True
    try:
        conn.cursor().execute(sql)
    except Exception:
        conn.cursor().execute("ROLLBACK")   # conn.rollback() does nothing in autocommit mode
        raise

    # B) default mode: psycopg2 opens the transaction (the file's BEGIN only gives a harmless warning)
    try:
        cur.execute(sql)
        conn.commit()
    except Exception:
        conn.rollback()
        raise

If a load fails in the middle, nothing from that file stays in the database.

## Rules the data follows

- Source names must equal `dwh.dim_source`: `fx_gold`, `world_bank`, `static_site`, `official_file`.
- `dim_product.product_id` is the stable id (SKU / URL slug). Every attribute change creates a new row with `is_current = true` and closes the old one (`valid_to`). Only one current row per product.
- `dim_currency` and `dim_indicator` are filled from the real data in staging, nothing is pre-seeded.
- Annual indicators have `period_month = NULL` in staging and `0` in `fact_indicator`. A missing value stays `NULL`; it is never filled.
- If staging holds the same key twice, the latest `observed_at` wins.
- `staging` tables have no UNIQUE / NOT NULL on purpose: the quality gate must find NULLs and duplicates before load.

## Tests and demo data

Run inside the running compose container. The tests only touch rows with test keys and delete them at the end:

    docker compose exec postgres psql -U eco_admin -d eco -f /sql/tests/test_scd2.sql
    docker compose exec postgres psql -U eco_admin -d eco -f /sql/tests/test_load_facts.sql

Each one ends with `PASSED`.

`sql/tests/demo_data.sql` fills staging with 30 days of MOCK data (10 `DEMO-*` products, USD, gold 24/21/18, inflation) and runs the three load files, so the serving views show numbers:

    docker compose exec postgres psql -U eco_admin -d eco -f /sql/tests/demo_data.sql

Use it on dev databases only: it uses the real currency codes, so it would overwrite real data for the same days. Wipe everything with `docker compose down -v`.

## Known limitation

If a product attribute changes and the same day is loaded again, that day can hold one price per product version. Normal runs (one load per day) are not affected.
## Basket index

`serving.v_basket_index` computes `Index_t = 100 * SUM(w_i * p_i,t / p_i,0)` over the products listed in `dwh.basket_weights` (product_id, weight; weights are divided by their total). The base date is the first day on which every basket product has a price; a product without a price takes its last price from the previous 3 days (fill-forward), and a day that is still incomplete shows `index_value = NULL` with `products_missing > 0`.
The table is empty until the real basket is chosen (then the view returns no rows): insert the product_ids used by the scraper with their weights. `sql/tests/test_basket_index.sql` checks the formula with hand-calculated numbers.
### Performance

On synthetic data (15,000 price rows, 20 basket products, 400 days) the first version of the view took about 2.4 s because the fill-forward used a LATERAL subquery per product and day. It now uses a window function (MAX(...) OVER) and takes about 35 ms with identical output; the existing indexes on date_key and product_key are enough.

