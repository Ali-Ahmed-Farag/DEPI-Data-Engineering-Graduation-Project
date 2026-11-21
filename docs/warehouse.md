\# Warehouse (PostgreSQL) - R3



Everything lives in one PostgreSQL 16 server with two databases: `eco` (our data) and `airflow` (Airflow metadata). Inside `eco` data moves `raw -> staging -> dwh -> serving`, and `ops` holds monitoring tables. The star schema is drawn in \[erd/warehouse\_erd.md](erd/warehouse\_erd.md).



\## Schemas and who can touch what



| Schema | Content | Written by | Read by |

|---|---|---|---|

| `raw` | api\_responses, html\_pages, files (source data as collected) | connectors via `raw\_store.py` | etl\_user |

| `staging` | products, prices\_clean, fx\_gold\_clean, indicators\_clean | transform step | etl\_user |

| `dwh` | dim\_date, dim\_source, dim\_product (SCD2), dim\_currency, dim\_indicator, fact\_price, fact\_gold\_fx, fact\_indicator | load SQL in `sql/load/` | etl\_user |

| `ops` | pipeline\_runs, records\_rejected, quality\_results | `ops\_log.py` | etl\_user |

| `serving` | views only | created by `sql/60\_\*.sql`, `sql/65\_\*.sql` | \*\*reader\*\* (API and Grafana) |



\- `etl\_user` owns every schema and writes to raw/staging/dwh/ops. `reader` has SELECT on `serving` only; it cannot see the other schemas. Views run with their owner's rights, so a serving view can read `dwh` / `ops` for `reader`.

\- The admin user (`POSTGRES\_USER`, see `.env`) is only used to run `sql/\*.sql` at first start.



\## How the database is created



On the FIRST start with an empty `pgdata` volume, `docker/postgres/init/02\_run\_sql.sh` runs every top-level `sql/\*.sql` in name order (00 roles, 10 schemas, 20 raw, 30 staging, 40 dwh, 50 ops, 60/65 serving). Role passwords come from `.env` (`ETL\_USER\_PASSWORD`, `READER\_PASSWORD`). Init scripts do NOT run again on an existing volume: use `docker compose down -v` to start clean.

Sub-folders `sql/load/` and `sql/tests/` are not run at start on purpose.



\## Loading the warehouse (for Airflow, task `load`)



One file per source, each file is ONE transaction (dimensions first, then facts):



| File | Source | Reads | Writes |

|---|---|---|---|

| `sql/load/load\_prices.sql` | static\_site | staging.products, staging.prices\_clean | dim\_product (SCD2), fact\_price |

| `sql/load/load\_fx\_gold.sql` | fx\_gold | staging.fx\_gold\_clean | dim\_currency, fact\_gold\_fx |

| `sql/load/load\_indicators.sql` | world\_bank, official\_file | staging.indicators\_clean | dim\_indicator, fact\_indicator |



Run them after the quality gate passed. They are safe to run again (idempotent): facts are UPSERTed on their primary key and the SCD2 only closes rows whose attributes changed.



From Python run the whole file text in one `execute`. Two ways work (both tested):

```python

sql = open("sql/load/load\_prices.sql", encoding="utf-8").read()



\# A) autocommit: the file's own BEGIN/COMMIT control the transaction

conn.autocommit = True

try:

&#x20;   conn.cursor().execute(sql)

except Exception:

&#x20;   conn.cursor().execute("ROLLBACK")   # conn.rollback() does nothing in autocommit mode

&#x20;   raise



\# B) default mode: psycopg2 opens the transaction (the file's BEGIN only gives a harmless warning)

try:

&#x20;   cur.execute(sql); conn.commit()

except Exception:

&#x20;   conn.rollback(); raise

```

If a load fails in the middle, nothing from that file stays in the database.



\## Rules the data follows



\- Source names must equal `dwh.dim\_source`: `fx\_gold`, `world\_bank`, `static\_site`, `official\_file`.

\- `dim\_product.product\_id` is the stable id (SKU / URL slug); every attribute change creates a new row with `is\_current = true` and closes the old one (`valid\_to`). Only one current row per product.

\- `dim\_currency` and `dim\_indicator` are filled from the real data in staging, nothing is pre-seeded.

\- Annual indicators have `period\_month = NULL` in staging and `0` in `fact\_indicator`. A missing value stays `NULL`; it is never filled.

\- If staging holds the same key twice, the latest `observed\_at` wins.

\- `staging` tables have no UNIQUE / NOT NULL on purpose: the quality gate must find NULLs and duplicates before load.



\## Tests



Run inside the running compose container (they only touch rows with test keys and delete them at the end):

```

docker compose exec postgres psql -U eco\_admin -d eco -f /sql/tests/test\_scd2.sql

docker compose exec postgres psql -U eco\_admin -d eco -f /sql/tests/test\_load\_facts.sql

```

Each one ends with `PASSED`. `sql/tests/sample\_data.sql` is demo data with placeholder codes; never load it into a real warehouse.



\## Known limitation



If a product attribute changes and the same day is loaded again, that day can hold one price per product version. Normal runs (one load per day) are not affected.

