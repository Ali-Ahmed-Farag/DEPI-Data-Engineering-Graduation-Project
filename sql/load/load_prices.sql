-- load_prices.sql   (R3, tasks 3.14 / 4.2 / 4.3 / 4.8)
-- Source: static_site.  staging.products + staging.prices_clean -> dwh.dim_product (SCD2) + dwh.fact_price
-- ONE transaction: dimensions first, then facts (checklist sections 10 and 14).
-- Safe to run many times: the SCD2 closes only changed rows and the facts are UPSERTed.

BEGIN;

-- SCD2 step 1: close the current version when name / category / unit changed
UPDATE dwh.dim_product AS target
SET valid_to = CURRENT_DATE - 1,
    is_current = FALSE
FROM (
    SELECT DISTINCT ON (TRIM(product_id))
           TRIM(product_id) AS product_id,
           TRIM(name)       AS name,
           TRIM(category)   AS category,
           TRIM(unit)       AS unit
    FROM staging.products
    WHERE product_id IS NOT NULL AND TRIM(product_id) <> ''
    ORDER BY TRIM(product_id)
) AS source
WHERE target.product_id = source.product_id
  AND target.is_current
  AND (   LOWER(TRIM(target.name))     IS DISTINCT FROM LOWER(source.name)
       OR LOWER(TRIM(target.category)) IS DISTINCT FROM LOWER(source.category)
       OR LOWER(TRIM(target.unit))     IS DISTINCT FROM LOWER(source.unit));

-- SCD2 step 2: insert a version for new products and for products just closed
INSERT INTO dwh.dim_product (product_id, name, category, unit, valid_from, valid_to, is_current)
SELECT source.product_id, source.name, source.category, source.unit, CURRENT_DATE, NULL, TRUE
FROM (
    SELECT DISTINCT ON (TRIM(product_id))
           TRIM(product_id) AS product_id,
           TRIM(name)       AS name,
           TRIM(category)   AS category,
           TRIM(unit)       AS unit
    FROM staging.products
    WHERE product_id IS NOT NULL AND TRIM(product_id) <> ''
    ORDER BY TRIM(product_id)
) AS source
WHERE NOT EXISTS (
    SELECT 1 FROM dwh.dim_product AS target
    WHERE target.product_id = source.product_id AND target.is_current
);

-- Facts: look up the surrogate keys, then UPSERT.
-- DISTINCT ON keeps the latest observation if staging holds the same
-- (product, source, day) twice, so ON CONFLICT never sees a key twice.
INSERT INTO dwh.fact_price (product_key, source_key, date_key, price, unit_price)
SELECT DISTINCT ON (p.product_key, src.source_key, dt.date_key)
       p.product_key, src.source_key, dt.date_key, s.price, s.unit_price
FROM staging.prices_clean s
JOIN dwh.dim_product p   ON p.product_id = TRIM(s.product_id) AND p.is_current
JOIN dwh.dim_source  src ON src.source_name = s.source
JOIN dwh.dim_date    dt  ON dt.full_date = s.price_date
WHERE s.price IS NOT NULL
ORDER BY p.product_key, src.source_key, dt.date_key, s.observed_at DESC NULLS LAST
ON CONFLICT (product_key, source_key, date_key)
DO UPDATE SET price      = EXCLUDED.price,
              unit_price = EXCLUDED.unit_price,
              loaded_at  = now();

COMMIT;