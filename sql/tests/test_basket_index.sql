-- test_basket_index.sql  (R3, tasks 6.1 / 6.2)
-- Tests serving.v_basket_index with hand-calculated numbers.
-- NOT run at container start (it lives in sql/tests/).
--
--   docker compose exec postgres psql -U eco_admin -d eco -f /sql/tests/test_basket_index.sql
--
-- Everything runs inside ONE transaction that is ROLLED BACK at the end, so the
-- real basket weights and prices are not touched (the test empties
-- dwh.basket_weights inside the transaction).
--
-- Setup: two products, weights 3 and 2 (total 5, so normalised 0.6 and 0.4).
--   A (0.6): day2=110 day3=120 (nothing after)
--   B (0.4): day1 none, day2=200 day3=210 day4=220 day5=230 day6=240 day7=250
-- Expected:
--   day1: not in the view (before the base date)
--   day2: base date (first day where both have a price) -> 100.00
--   day3: 100*(0.6*120/110 + 0.4*210/200) = 107.45
--   day4: A filled from day3 (120)        -> 109.45, products_filled = 1
--   day6: A filled for the 3rd day        -> 113.45
--   day7: A missing (more than 3 days)    -> index_value NULL, products_missing = 1

\set ON_ERROR_STOP on
\echo '== basket index test: start =='
BEGIN;

DELETE FROM dwh.basket_weights;
INSERT INTO dwh.basket_weights VALUES ('TESTA', 3), ('TESTB', 2);

INSERT INTO dwh.dim_product (product_id, name, category, unit, valid_from, is_current) VALUES
    ('TESTA', 'Test A', 'Test', 'kg', '2026-12-01', TRUE),
    ('TESTB', 'Test B', 'Test', 'kg', '2026-12-01', TRUE);

INSERT INTO dwh.fact_price (product_key, source_key, date_key, price)
SELECT p.product_key,
       (SELECT source_key FROM dwh.dim_source WHERE source_name = 'static_site'),
       to_char(v.d, 'YYYYMMDD')::int,
       v.price
FROM (VALUES
    ('TESTA', DATE '2026-12-02', 110), ('TESTA', DATE '2026-12-03', 120),
    ('TESTB', DATE '2026-12-02', 200), ('TESTB', DATE '2026-12-03', 210),
    ('TESTB', DATE '2026-12-04', 220), ('TESTB', DATE '2026-12-05', 230),
    ('TESTB', DATE '2026-12-06', 240), ('TESTB', DATE '2026-12-07', 250)
) AS v(pid, d, price)
JOIN dwh.dim_product p ON p.product_id = v.pid AND p.is_current;

DO $$
DECLARE r serving.v_basket_index%ROWTYPE;
BEGIN
    ASSERT (SELECT count(*) FROM serving.v_basket_index) = 6,
           'check 1 failed: expected 6 rows (day2..day7)';
    ASSERT NOT EXISTS (SELECT 1 FROM serving.v_basket_index WHERE index_date = '2026-12-01'),
           'check 1 failed: nothing may be shown before the base date';
    ASSERT (SELECT MAX(base_date) FROM serving.v_basket_index) = '2026-12-02',
           'check 1 failed: base date must be the first day with all prices (day2)';

    SELECT * INTO r FROM serving.v_basket_index WHERE index_date = '2026-12-02';
    ASSERT r.index_value = 100.00, 'check 2 failed: index on the base date must be 100, got ' || r.index_value;

    SELECT * INTO r FROM serving.v_basket_index WHERE index_date = '2026-12-03';
    ASSERT r.index_value = 107.45, 'check 3 failed: day3 index should be 107.45, got ' || r.index_value;
    ASSERT r.products_filled = 0, 'check 3 failed: nothing is filled on day3';

    SELECT * INTO r FROM serving.v_basket_index WHERE index_date = '2026-12-04';
    ASSERT r.index_value = 109.45, 'check 4 failed: day4 index should be 109.45, got ' || r.index_value;
    ASSERT r.products_filled = 1, 'check 4 failed: day4 must show 1 filled product';

    SELECT * INTO r FROM serving.v_basket_index WHERE index_date = '2026-12-06';
    ASSERT r.index_value = 113.45, 'check 5 failed: day6 (3rd filled day) should be 113.45, got ' || r.index_value;

    SELECT * INTO r FROM serving.v_basket_index WHERE index_date = '2026-12-07';
    ASSERT r.index_value IS NULL, 'check 6 failed: day7 must be marked missing (NULL)';
    ASSERT r.products_missing = 1, 'check 6 failed: day7 must show 1 missing product';
END $$;
\echo 'checks 1-6 OK: base date, formula, normalised weights, fill-forward limit, gap marked NULL'

DO $$
BEGIN
    DELETE FROM dwh.basket_weights;
    ASSERT (SELECT count(*) FROM serving.v_basket_index) = 0,
           'check 7 failed: an empty basket must give no rows';
END $$;
\echo 'check 7 OK: empty basket gives no rows'

ROLLBACK;
\echo '== basket index test: PASSED (rolled back, nothing was changed) =='