-- Sample Data for Egypt Economic Intelligence Platform
-- Purpose: Test DWH dimensions and facts loading.
-- Run after all DDL scripts have been executed.

BEGIN;

-- 1. Sample products (safe to re-run)
INSERT INTO dwh.dim_product
    (product_id, name, category, unit, valid_from, valid_to, is_current)
VALUES
    ('P001', 'Gold 24K', 'Gold', 'gram', CURRENT_DATE, NULL, TRUE),
    ('P002', 'Gold 21K', 'Gold', 'gram', CURRENT_DATE, NULL, TRUE)
ON CONFLICT (product_id) WHERE is_current
DO UPDATE SET
    name = EXCLUDED.name,
    category = EXCLUDED.category,
    unit = EXCLUDED.unit
WHERE dwh.dim_product.name IS DISTINCT FROM EXCLUDED.name
   OR dwh.dim_product.category IS DISTINCT FROM EXCLUDED.category
   OR dwh.dim_product.unit IS DISTINCT FROM EXCLUDED.unit;

-- 2. Sample currencies and gold (safe to re-run)
INSERT INTO dwh.dim_currency (code, kind, karat)
VALUES
    ('EGP', 'currency', NULL),
    ('USD', 'currency', NULL),
    ('GOLD_24K', 'gold', 24),
    ('GOLD_21K', 'gold', 21)
ON CONFLICT DO NOTHING;
-- 3. Sample economic indicators (safe to re-run)
INSERT INTO dwh.dim_indicator
    (indicator_code, indicator_name, unit, frequency)
VALUES
    ('EG_INFLATION', 'Egypt Inflation Rate', 'percent', 'monthly'),
    ('EG_GDP', 'Egypt GDP Growth', 'percent', 'annual')
ON CONFLICT (indicator_code)
DO UPDATE SET
    indicator_name = EXCLUDED.indicator_name,
    unit = EXCLUDED.unit,
    frequency = EXCLUDED.frequency
WHERE dwh.dim_indicator.indicator_name
          IS DISTINCT FROM EXCLUDED.indicator_name
   OR dwh.dim_indicator.unit IS DISTINCT FROM EXCLUDED.unit
   OR dwh.dim_indicator.frequency IS DISTINCT FROM EXCLUDED.frequency;

COMMIT;
