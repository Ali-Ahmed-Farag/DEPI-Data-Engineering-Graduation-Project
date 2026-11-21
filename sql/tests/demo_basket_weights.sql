-- demo_basket_weights.sql   (R3)   *** MOCK DATA, DEV ONLY ***
-- Weights for the 10 DEMO-* products created by demo_data.sql (they add up to 1).
-- Run by demo_data.sql; you can also run it alone:
--   docker compose exec postgres psql -U eco_admin -d eco -f /sql/tests/demo_basket_weights.sql

\set ON_ERROR_STOP on
DELETE FROM dwh.basket_weights WHERE product_id LIKE 'DEMO-%';
INSERT INTO dwh.basket_weights (product_id, weight) VALUES
    ('DEMO-rice',     0.15),
    ('DEMO-sugar',    0.10),
    ('DEMO-flour',    0.10),
    ('DEMO-lentils',  0.08),
    ('DEMO-pasta',    0.07),
    ('DEMO-oil',      0.15),
    ('DEMO-milk',     0.10),
    ('DEMO-chicken',  0.15),
    ('DEMO-tomatoes', 0.05),
    ('DEMO-tea',      0.05);
\echo 'demo basket weights loaded (sum = 1.00)'