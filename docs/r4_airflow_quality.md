# Role 4: Airflow Orchestration & Data Quality (documentation)

## What it does
Airflow coordinates extraction, raw persistence, staging transformation, data-quality checks, warehouse loading, and monitoring in `ops.*`.

| Component | File | Responsibility |
|---|---|---|
| DAG template | `src/common/pipeline.py` | `make_source_dag()` builds the standard 7-task pipeline for each source |
| Monitoring logger | `src/common/ops_log.py` | Only writer to `ops.pipeline_runs`, `ops.records_rejected`, `ops.quality_results` |
| Quality checks | `src/quality/checks.py` | Pre-load critical checks (`quality_gate`) and post-load warning checks (`post_load_checks`) |

## Standard DAG Task Flow

    start_run -> extract_and_validate -> transform -> quality_gate -> load -> post_load_checks -> finish_run

- **Retries & failure tracking:** `retries=3`, `retry_delay=5 minutes`, `catchup=False`.
- **Final failure callback:** `_on_failure` updates `ops.pipeline_runs` with `status='failed'` and `error_message` when retries are exhausted.
- **Timezone:** `Africa/Cairo` (`AIRFLOW__CORE__DEFAULT_TIMEZONE: Africa/Cairo` in `docker-compose.yml` and `pendulum` start dates).

## Scheduled DAGs
| DAG ID | File | Source | Schedule (Africa/Cairo) |
|---|---|---|---|
| `fx_gold_daily` | `dags/fx_gold_daily.py` | `fx_gold` | `0 6 * * *` (daily at 06:00) |
| `world_bank_weekly` | `dags/world_bank_weekly.py` | `world_bank` | `0 6 * * 0` (weekly, Sunday at 06:00) |
| `official_file_monthly` | `dags/official_file_monthly.py` | `official_file` | `0 6 1 * *` (monthly, 1st at 06:00) |
| `hello_dag` | `dags/hello_dag.py` | `test` | Sample DAG for setup verification |

> Note: Airflow is configured with `AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION: "true"`. Unpause active DAGs in the UI (`http://localhost:8080`) or via `airflow dags unpause <dag_id>`.

## Quality Checks (`src/quality/checks.py`)
All results are logged to `ops.quality_results` via `ops_log.log_quality()`.

### Critical Checks (`phase='pre_load'`, `severity='critical'`)
Executed in `quality_gate` before `load`. Any failed check raises `AirflowFailException` and stops warehouse loading:
- `row_count`: ensures `staging.*` has at least 1 row for the source.
- `nulls`: checks required key/value columns (`world_bank` allows `value IS NULL` and `period_month IS NULL` per task 4.10).
- `duplicates`: checks uniqueness on the natural key in staging.
- `price_range`: ensures `price > 0` (`prices_clean`), `rate > 0` (`fx_gold_clean`), and `CPI_URBAN_INDEX > 0` (`indicators_clean`).

### Warning Checks (`phase='post_load'`, `severity='warning'`)
Executed in `post_load_checks` after `load`. Failures are logged to `ops.quality_results` and Airflow logs without failing the DAG:
- `row_count`: warns if loaded rows in the last 24h dropped by > 30% compared to the previous successful run.
- `freshness`: warns if the latest observed date in `dwh` exceeds the source threshold (`fx_gold`: 3 days, `static_site`: 2 days, `official_file`: 365 days, `world_bank`: 730 days).
- `price_jump`: warns if any daily series in `dwh.fact_price` or `dwh.fact_gold_fx` changed by > 50% day-over-day.

## Verification & Tests
- Unit tests: `tests/test_r4_quality.py` (pre-load checks, post-load warnings, and `ops_log` helpers).
- Airflow CLI check: `docker exec eco_airflow_scheduler airflow dags list-import-errors`