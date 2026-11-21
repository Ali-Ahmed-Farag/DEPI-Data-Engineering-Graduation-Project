-- test_scd2.sql  (R3, task 2.11 / 4.7)
-- Tests the SCD2 load in sql/load/load_dim_product.sql.
-- NOT run at container start (it lives in sql/tests/).
--
-- Run inside the compose postgres container:
--   docker compose exec postgres psql -U eco_admin -d eco -f /sql/tests/test_scd2.sql
--
-- Only touches rows whose product_id starts with 'TEST'. They are removed
-- at the start and at the end, so real data is never changed.
-- Any failed check stops the script with an error; success ends with PASSED.

\set ON_ERROR_STOP on
\echo '== SCD2 test: start =='

-- clean slate (only TEST rows)
DELETE FROM dwh.dim_product  WHERE product_id LIKE 'TEST%';
DELETE FROM staging.products WHERE product_id LIKE 'TEST%';

-- 1) first load: two new products -> two current versions
INSERT INTO staging.products (product_id, name, category, unit) VALUES
    ('TEST001', 'Gold Ring',     'Jewelry', 'gram'),
    ('TEST002', 'Gold Necklace', 'Jewelry', 'gram');
\i /sql/load/load_dim_product.sql

DO $$
BEGIN
    ASSERT (SELECT count(*) FROM dwh.dim_product
            WHERE product_id LIKE 'TEST%') = 2,
           'check 1 failed: expected 2 rows after the first load';
    ASSERT (SELECT count(*) FROM dwh.dim_product
            WHERE product_id LIKE 'TEST%' AND is_current AND valid_to IS NULL) = 2,
           'check 1 failed: both rows must be current with valid_to NULL';
END $$;
\echo 'check 1 OK: first load creates 2 current versions'

-- 2) idempotency: same staging, load again -> nothing changes
\i /sql/load/load_dim_product.sql
DO $$
BEGIN
    ASSERT (SELECT count(*) FROM dwh.dim_product
            WHERE product_id LIKE 'TEST%') = 2,
           'check 2 failed: loading twice must not add rows';
END $$;
\echo 'check 2 OK: loading twice gives the same rows (idempotent)'

-- 3) category change -> old version closed, new current version added
UPDATE staging.products SET category = 'Accessories' WHERE product_id = 'TEST001';
\i /sql/load/load_dim_product.sql

DO $$
BEGIN
    ASSERT (SELECT count(*) FROM dwh.dim_product
            WHERE product_id = 'TEST001') = 2,
           'check 3 failed: TEST001 must have exactly 2 versions';
    ASSERT (SELECT count(*) FROM dwh.dim_product
            WHERE product_id = 'TEST001' AND is_current) = 1,
           'check 3 failed: TEST001 must have exactly 1 current version';
    ASSERT (SELECT category FROM dwh.dim_product
            WHERE product_id = 'TEST001' AND is_current) = 'Accessories',
           'check 3 failed: the current version must hold the new category';
    ASSERT (SELECT category FROM dwh.dim_product
            WHERE product_id = 'TEST001' AND NOT is_current) = 'Jewelry',
           'check 3 failed: the old version must keep the old category';
    ASSERT (SELECT valid_to FROM dwh.dim_product
            WHERE product_id = 'TEST001' AND NOT is_current) IS NOT NULL,
           'check 3 failed: the old version must have valid_to set';
END $$;
\echo 'check 3 OK: category change closes the old version and opens a new one'

-- 4) the unchanged product must not get a second version
DO $$
BEGIN
    ASSERT (SELECT count(*) FROM dwh.dim_product
            WHERE product_id = 'TEST002') = 1,
           'check 4 failed: unchanged TEST002 must keep a single version';
END $$;
\echo 'check 4 OK: unchanged product keeps one version'

-- cleanup
DELETE FROM dwh.dim_product  WHERE product_id LIKE 'TEST%';
DELETE FROM staging.products WHERE product_id LIKE 'TEST%';

\echo '== SCD2 test: PASSED =='