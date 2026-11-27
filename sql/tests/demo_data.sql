-- demo_data.sql   (R3, task 2.10 / 3.15)   *** MOCK DATA, DEV ONLY ***
-- Fills STAGING with 30 days of fake data that looks like the real data, then
-- runs the three load files, so the serving views and the dashboards show numbers
-- before the real pipeline has collected enough history.
--
--   docker compose exec postgres psql -U eco_admin -d eco -f /sql/tests/demo_data.sql
--
-- Products are named DEMO-*. The currency / gold / indicator rows use the REAL
-- codes (USD, XAU 24/21/18, FP.CPI.TOTL.ZG) because the serving views look for
-- them, so on a database that already has real data for the same days the demo
-- values would overwrite them. Use it on your own dev database only.
-- To wipe everything and start clean:  docker compose down -v

\set ON_ERROR_STOP on
\echo '== demo data: start =='

-- re-runnable: remove the demo rows of an earlier run from staging
DELETE FROM staging.products     WHERE product_id LIKE 'DEMO-%';
DELETE FROM staging.prices_clean WHERE product_id LIKE 'DEMO-%';
DELETE FROM staging.fx_gold_clean
 WHERE source = 'fx_gold' AND code IN ('USD', 'XAU')
   AND rate_date BETWEEN '2026-10-22' AND '2026-11-20';
DELETE FROM staging.indicators_clean
 WHERE source = 'world_bank' AND indicator_code = 'FP.CPI.TOTL.ZG' AND country = 'EGY';

-- 10 staple products: id, name, category, unit, base price (EGP)
CREATE TEMP TABLE demo_products (product_id text, name text, category text, unit text, base numeric, idx int);
INSERT INTO demo_products VALUES
    ('DEMO-rice',     'Rice',           'Grains',     'kg', 32,  1),
    ('DEMO-sugar',    'Sugar',          'Grains',     'kg', 28,  2),
    ('DEMO-flour',    'Flour',          'Grains',     'kg', 18,  3),
    ('DEMO-lentils',  'Lentils',        'Grains',     'kg', 55,  4),
    ('DEMO-pasta',    'Pasta',          'Grains',     'kg', 24,  5),
    ('DEMO-oil',      'Cooking oil',    'Oils',       'l',  75,  6),
    ('DEMO-milk',     'Milk',           'Dairy',      'l',  38,  7),
    ('DEMO-chicken',  'Chicken',        'Meat',       'kg', 95,  8),
    ('DEMO-tomatoes', 'Tomatoes',       'Vegetables', 'kg', 20,  9),
    ('DEMO-tea',      'Tea',            'Beverages',  'kg', 210, 10);

INSERT INTO staging.products (product_id, name, category, unit)
SELECT product_id, name, category, unit FROM demo_products;

-- price = base * (1 + slow upward trend + small wave), one row per product per day
INSERT INTO staging.prices_clean (product_id, source, price, unit_price, currency, price_date, observed_at)
SELECT p.product_id, 'static_site',
       round(p.base * (1 + 0.004 * n + 0.012 * sin(n * 0.7 + p.idx)::numeric), 2),
       round(p.base * (1 + 0.004 * n + 0.012 * sin(n * 0.7 + p.idx)::numeric), 2),
       'EGP',
       d::date,
       (d::date + time '06:00') AT TIME ZONE 'Africa/Cairo'
FROM demo_products p
CROSS JOIN generate_series(0, 29) AS n
CROSS JOIN LATERAL (SELECT DATE '2026-10-22' + n AS d) AS x;

-- USD / EGP and gold per gram (24K, 21K = 21/24 of it, 18K = 18/24 of it)
INSERT INTO staging.fx_gold_clean (source, code, kind, karat, rate, rate_date, observed_at)
SELECT 'fx_gold', 'USD', 'currency', NULL,
       round(48.5 + 0.05 * n + 0.15 * sin(n * 0.9)::numeric, 4),
       d::date, (d::date + time '06:00') AT TIME ZONE 'Africa/Cairo'
FROM generate_series(0, 29) AS n CROSS JOIN LATERAL (SELECT DATE '2026-10-22' + n AS d) AS x;

INSERT INTO staging.fx_gold_clean (source, code, kind, karat, rate, rate_date, observed_at)
SELECT 'fx_gold', 'XAU', 'gold', k,
       round((5400 + 6 * n + 25 * sin(n * 0.5)::numeric) * k / 24.0, 2),
       d::date, (d::date + time '06:00') AT TIME ZONE 'Africa/Cairo'
FROM generate_series(0, 29) AS n
CROSS JOIN (VALUES (24), (21), (18)) AS ks(k)
CROSS JOIN LATERAL (SELECT DATE '2026-10-22' + n AS d) AS x;

-- annual inflation (World Bank style); the last year is a gap (NULL), as in real data
INSERT INTO staging.indicators_clean
    (source, indicator_code, indicator_name, unit, frequency, country, period_year, period_month, value)
SELECT 'world_bank', 'FP.CPI.TOTL.ZG', 'Inflation, consumer prices (annual %)', '%', 'annual', 'EGY', y, NULL,
       CASE WHEN y = 2025 THEN NULL ELSE v END
FROM (VALUES (2018, 20.9), (2019, 13.9), (2020, 5.7), (2021, 4.5), (2022, 8.5),
             (2023, 33.9), (2024, 28.3), (2025, NULL)) AS t(y, v);

\i /sql/load/load_prices.sql
\i /sql/load/load_fx_gold.sql
\i /sql/load/load_indicators.sql

\echo '== demo data: loaded. Row counts: =='
SELECT 'dim_product' AS table_name, count(*) FROM dwh.dim_product WHERE product_id LIKE 'DEMO-%'
UNION ALL SELECT 'fact_price',     count(*) FROM dwh.fact_price
UNION ALL SELECT 'fact_gold_fx',   count(*) FROM dwh.fact_gold_fx
UNION ALL SELECT 'fact_indicator', count(*) FROM dwh.fact_indicator;
\echo '== demo data: DONE =='
\i /sql/tests/demo_basket_weights.sql