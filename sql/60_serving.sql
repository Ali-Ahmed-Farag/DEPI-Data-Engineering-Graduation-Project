-- 60_serving.sql
-- Owner: R3 (Warehouse & SQL Lead)
-- serving layer: VIEWS ONLY. FastAPI and Grafana read from here with the
-- `reader` role (SELECT on serving only, see 10_schemas.sql).
-- Views run with their owner's rights (etl_user), so they can read dwh/ops
-- while reader has no direct access to those schemas.
--
-- Column names are the contract with R5: do not rename without telling R5.
-- The tables are empty until data is loaded (sample data: task 2.10), so
-- these views return no rows yet, but their columns are final.

SET ROLE etl_user;

-- GET /prices/latest : latest price of every product per source
CREATE OR REPLACE VIEW serving.v_latest_prices AS
SELECT DISTINCT ON (p.product_id, s.source_name)
       p.product_id,
       p.name        AS product_name,
       p.category,
       p.unit,
       s.source_name AS source,
       d.full_date   AS price_date,
       f.price,
       f.unit_price
FROM dwh.fact_price f
JOIN dwh.dim_product p ON p.product_key = f.product_key
JOIN dwh.dim_source  s ON s.source_key  = f.source_key
JOIN dwh.dim_date    d ON d.date_key    = f.date_key
ORDER BY p.product_id, s.source_name, d.full_date DESC;

-- GET /products/{id}/history : price history with day-over-day change
CREATE OR REPLACE VIEW serving.v_product_history AS
SELECT p.product_id,
       p.name        AS product_name,
       p.category,
       s.source_name AS source,
       d.full_date   AS price_date,
       f.price,
       f.unit_price,
       f.price / NULLIF(LAG(f.price) OVER (
           PARTITION BY p.product_id, s.source_name
           ORDER BY d.full_date), 0) - 1 AS pct_change
FROM dwh.fact_price f
JOIN dwh.dim_product p ON p.product_key = f.product_key
JOIN dwh.dim_source  s ON s.source_key  = f.source_key
JOIN dwh.dim_date    d ON d.date_key    = f.date_key;

-- GET /index : basket price index (checklist section 11)
--   Index_t = 100 * SUM( w_i * p_i,t / p_i,0 )      SUM(w_i) = 1
-- * basket and weights: dwh.basket_weights (weights are divided by their total)
-- * p_i,t: average price of the product over all sources on that day
-- * fill-forward: a product without a price on a day takes its last price from
--   the previous 3 days (change the 3 below to allow more or fewer days)
-- * base date: the first day on which EVERY basket product has a price
-- * a day on which some product is still missing after the fill-forward gets
--   index_value NULL, so the gap stays visible and nothing is invented
-- Columns: index_date, index_value, products_count are the contract with R5;
-- the others were added at the end.
CREATE OR REPLACE VIEW serving.v_basket_index AS
WITH w AS (
    SELECT product_id,
           weight / SUM(weight) OVER () AS weight
    FROM dwh.basket_weights
),
basket_size AS (
    SELECT COUNT(*) AS n FROM w
),
observed AS (                                    -- real prices, one per product per day
    SELECT p.product_id, d.full_date, AVG(f.price) AS price
    FROM dwh.fact_price f
    JOIN dwh.dim_product p ON p.product_key = f.product_key
    JOIN dwh.dim_date    d ON d.date_key    = f.date_key
    JOIN w                 ON w.product_id  = p.product_id
    GROUP BY p.product_id, d.full_date
),
calendar AS (                                    -- every day between the first and last price
    SELECT d.full_date
    FROM dwh.dim_date d
    WHERE d.full_date BETWEEN (SELECT MIN(full_date) FROM observed)
                          AND (SELECT MAX(full_date) FROM observed)
),
grid AS (                                        -- every basket product x every day
    SELECT w.product_id, w.weight, c.full_date
    FROM w
    CROSS JOIN calendar c
),
marked AS (                                      -- date of the last real price up to each day
    SELECT g.product_id, g.weight, g.full_date,
           MAX(o.full_date) OVER (PARTITION BY g.product_id
                                  ORDER BY g.full_date) AS last_observed
    FROM grid g
    LEFT JOIN observed o ON o.product_id = g.product_id
                        AND o.full_date  = g.full_date
),
filled AS (                                      -- price of each basket product on each day
    SELECT m.product_id, m.weight, m.full_date,
           o.price, o.full_date AS observed_on
    FROM marked m
    LEFT JOIN observed o ON o.product_id = m.product_id
                        AND o.full_date  = m.last_observed
                        AND m.last_observed >= m.full_date - 3   -- max days of fill-forward
),
base AS (
    SELECT MIN(full_date) AS base_date
    FROM (SELECT full_date
          FROM filled
          GROUP BY full_date
          HAVING COUNT(price) = (SELECT n FROM basket_size)) complete_days
),
base_prices AS (
    SELECT f.product_id, f.price AS base_price
    FROM filled f
    JOIN base b ON f.full_date = b.base_date
)
SELECT f.full_date AS index_date,
       CASE WHEN COUNT(f.price) = (SELECT n FROM basket_size)
            THEN ROUND(100 * SUM(f.weight * f.price / bp.base_price), 2)
       END                                            AS index_value,
       COUNT(f.price)                                 AS products_count,
       (SELECT n FROM basket_size) - COUNT(f.price)   AS products_missing,
       COUNT(*) FILTER (WHERE f.observed_on < f.full_date) AS products_filled,
       MAX(b.base_date)                               AS base_date
FROM filled f
CROSS JOIN base b
JOIN base_prices bp ON bp.product_id = f.product_id
WHERE f.full_date >= b.base_date
GROUP BY f.full_date;

-- GET /pipeline/status : last run of every source
CREATE OR REPLACE VIEW serving.v_pipeline_status AS
SELECT DISTINCT ON (source)
       source,
       dag_id,
       run_date,
       status,
       started_at,
       finished_at,
       records_count,
       error_message
FROM ops.pipeline_runs
ORDER BY source, started_at DESC, run_id DESC;

-- Pipeline-health dashboard: rejected records grouped by cause
CREATE OR REPLACE VIEW serving.v_rejected_summary AS
SELECT source,
       stage,
       reason,
       COUNT(*)           AS rejected_count,
       MAX(rejected_at)   AS last_rejected_at
FROM ops.records_rejected
GROUP BY source, stage, reason;

-- Pipeline-health dashboard: latest result of every quality check
CREATE OR REPLACE VIEW serving.v_quality_summary AS
SELECT DISTINCT ON (source, check_name)
       source,
       check_name,
       severity,
       phase,
       passed,
       metric_value,
       details,
       checked_at
FROM ops.quality_results
ORDER BY source, check_name, checked_at DESC, id DESC;

RESET ROLE;