-- test_load_facts.sql  (R3, tasks 4.3 / 4.4 / 4.6 / 4.8)
-- Tests sql/load/load_prices.sql, load_fx_gold.sql and load_indicators.sql.
-- NOT run at container start (it lives in sql/tests/).
--
-- Run inside the compose postgres container:
--   docker compose exec postgres psql -U eco_admin -d eco -f /sql/tests/test_load_facts.sql
--
-- Uses only test keys (product_id TESTP1, currency codes TST / TSTG,
-- indicator TEST.IND). Assertions look at these keys only, and everything
-- the test created is removed at the start and at the end.
-- Any failed check stops the script with an error; success ends with PASSED.

\set ON_ERROR_STOP on
\echo '== load facts test: start =='

-- ---------------------------------------------------------------- cleanup
\echo 'cleanup of old test rows'
DELETE FROM dwh.fact_price     WHERE product_key   IN (SELECT product_key   FROM dwh.dim_product   WHERE product_id LIKE 'TEST%');
DELETE FROM dwh.dim_product    WHERE product_id LIKE 'TEST%';
DELETE FROM dwh.fact_gold_fx   WHERE currency_key  IN (SELECT currency_key  FROM dwh.dim_currency  WHERE code IN ('TST', 'TSTG'));
DELETE FROM dwh.dim_currency   WHERE code IN ('TST', 'TSTG');
DELETE FROM dwh.fact_indicator WHERE indicator_key IN (SELECT indicator_key FROM dwh.dim_indicator WHERE indicator_code = 'TEST.IND');
DELETE FROM dwh.dim_indicator  WHERE indicator_code = 'TEST.IND';
DELETE FROM staging.products        WHERE product_id LIKE 'TEST%';
DELETE FROM staging.prices_clean    WHERE product_id LIKE 'TEST%';
DELETE FROM staging.fx_gold_clean   WHERE code IN ('TST', 'TSTG');
DELETE FROM staging.indicators_clean WHERE indicator_code = 'TEST.IND';

-- ------------------------------------------------------------ test staging
INSERT INTO staging.products (product_id, name, category, unit)
VALUES ('TESTP1', 'Test Milk', 'Dairy', 'l');

-- day 1 is in staging TWICE (later observation = 41 must win); day 2 once
INSERT INTO staging.prices_clean (product_id, source, price, unit_price, currency, price_date, observed_at) VALUES
    ('TESTP1', 'static_site', 40, 40, 'EGP', '2026-11-01', '2026-11-01 06:00+02'),
    ('TESTP1', 'static_site', 41, 41, 'EGP', '2026-11-01', '2026-11-01 18:00+02'),
    ('TESTP1', 'static_site', 45, 45, 'EGP', '2026-11-02', '2026-11-02 06:00+02');

INSERT INTO staging.fx_gold_clean (source, code, kind, karat, rate, rate_date, observed_at) VALUES
    ('fx_gold', 'TST',  'currency', NULL, 50.0,   '2026-11-01', '2026-11-01 06:00+02'),
    ('fx_gold', 'TSTG', 'gold',     21,   3000.0, '2026-11-01', '2026-11-01 06:00+02');

INSERT INTO staging.indicators_clean (source, indicator_code, indicator_name, unit, frequency, country, period_year, period_month, value) VALUES
    ('world_bank', 'TEST.IND', 'Test indicator', '%', 'annual',  'TST', 2023, NULL, 5.5),
    ('world_bank', 'TEST.IND', 'Test indicator', '%', 'annual',  'TST', 2024, NULL, NULL),
    ('world_bank', 'TEST.IND', 'Test indicator', '%', 'monthly', 'TST', 2025, 3,    7.0);

-- ------------------------------------------------------- 1) first load
\i /sql/load/load_prices.sql
\i /sql/load/load_fx_gold.sql
\i /sql/load/load_indicators.sql

DO $$
BEGIN
    ASSERT (SELECT count(*) FROM dwh.fact_price fp
            JOIN dwh.dim_product p USING (product_key)
            WHERE p.product_id = 'TESTP1') = 2,
           'check 1 failed: expected 2 price facts (duplicate staging row must collapse)';
    ASSERT (SELECT fp.price FROM dwh.fact_price fp
            JOIN dwh.dim_product p USING (product_key)
            JOIN dwh.dim_date d USING (date_key)
            WHERE p.product_id = 'TESTP1' AND d.full_date = '2026-11-01') = 41,
           'check 1 failed: the latest observation (41) must win';
    ASSERT (SELECT count(*) FROM dwh.dim_currency WHERE code IN ('TST', 'TSTG')) = 2,
           'check 1 failed: expected 2 currency dimension rows';
    ASSERT (SELECT count(*) FROM dwh.fact_gold_fx f
            JOIN dwh.dim_currency c USING (currency_key)
            WHERE c.code IN ('TST', 'TSTG')) = 2,
           'check 1 failed: expected 2 gold/fx facts';
    ASSERT (SELECT count(*) FROM dwh.fact_indicator f
            JOIN dwh.dim_indicator i USING (indicator_key)
            WHERE i.indicator_code = 'TEST.IND') = 3,
           'check 1 failed: expected 3 indicator facts';
    ASSERT (SELECT count(*) FROM dwh.fact_indicator f
            JOIN dwh.dim_indicator i USING (indicator_key)
            WHERE i.indicator_code = 'TEST.IND' AND f.period_month = 0) = 2,
           'check 1 failed: annual data must be stored with period_month = 0';
    ASSERT (SELECT count(*) FROM dwh.fact_indicator f
            JOIN dwh.dim_indicator i USING (indicator_key)
            WHERE i.indicator_code = 'TEST.IND' AND f.value IS NULL) = 1,
           'check 1 failed: the gap (NULL value) must be kept as NULL';
END $$;
\echo 'check 1 OK: first load (keys, latest-wins, month 0, NULL kept)'

-- --------------------------------------- 2) idempotency: load everything again
\i /sql/load/load_prices.sql
\i /sql/load/load_fx_gold.sql
\i /sql/load/load_indicators.sql

DO $$
BEGIN
    ASSERT (SELECT count(*) FROM dwh.fact_price fp
            JOIN dwh.dim_product p USING (product_key)
            WHERE p.product_id = 'TESTP1') = 2,
           'check 2 failed: price facts changed after a second load';
    ASSERT (SELECT count(*) FROM dwh.dim_product WHERE product_id = 'TESTP1') = 1,
           'check 2 failed: second load must not add a product version';
    ASSERT (SELECT count(*) FROM dwh.fact_gold_fx f
            JOIN dwh.dim_currency c USING (currency_key)
            WHERE c.code IN ('TST', 'TSTG')) = 2,
           'check 2 failed: gold/fx facts changed after a second load';
    ASSERT (SELECT count(*) FROM dwh.dim_currency WHERE code IN ('TST', 'TSTG')) = 2,
           'check 2 failed: currency dimension changed after a second load';
    ASSERT (SELECT count(*) FROM dwh.fact_indicator f
            JOIN dwh.dim_indicator i USING (indicator_key)
            WHERE i.indicator_code = 'TEST.IND') = 3,
           'check 2 failed: indicator facts changed after a second load';
END $$;
\echo 'check 2 OK: loading twice gives the same numbers (idempotent)'

-- ------------------------------- 3) a corrected value is UPDATED, not duplicated
UPDATE staging.prices_clean SET price = 46, unit_price = 46
WHERE product_id = 'TESTP1' AND price_date = '2026-11-02';
\i /sql/load/load_prices.sql

DO $$
BEGIN
    ASSERT (SELECT count(*) FROM dwh.fact_price fp
            JOIN dwh.dim_product p USING (product_key)
            WHERE p.product_id = 'TESTP1') = 2,
           'check 3 failed: a corrected price must not add a row';
    ASSERT (SELECT fp.price FROM dwh.fact_price fp
            JOIN dwh.dim_product p USING (product_key)
            JOIN dwh.dim_date d USING (date_key)
            WHERE p.product_id = 'TESTP1' AND d.full_date = '2026-11-02') = 46,
           'check 3 failed: the corrected price (46) must replace the old one';
END $$;
\echo 'check 3 OK: corrected price is updated in place'

-- ------------------------------------------------------------------ cleanup
DELETE FROM dwh.fact_price     WHERE product_key   IN (SELECT product_key   FROM dwh.dim_product   WHERE product_id LIKE 'TEST%');
DELETE FROM dwh.dim_product    WHERE product_id LIKE 'TEST%';
DELETE FROM dwh.fact_gold_fx   WHERE currency_key  IN (SELECT currency_key  FROM dwh.dim_currency  WHERE code IN ('TST', 'TSTG'));
DELETE FROM dwh.dim_currency   WHERE code IN ('TST', 'TSTG');
DELETE FROM dwh.fact_indicator WHERE indicator_key IN (SELECT indicator_key FROM dwh.dim_indicator WHERE indicator_code = 'TEST.IND');
DELETE FROM dwh.dim_indicator  WHERE indicator_code = 'TEST.IND';
DELETE FROM staging.products        WHERE product_id LIKE 'TEST%';
DELETE FROM staging.prices_clean    WHERE product_id LIKE 'TEST%';
DELETE FROM staging.fx_gold_clean   WHERE code IN ('TST', 'TSTG');
DELETE FROM staging.indicators_clean WHERE indicator_code = 'TEST.IND';

\echo '== load facts test: PASSED =='