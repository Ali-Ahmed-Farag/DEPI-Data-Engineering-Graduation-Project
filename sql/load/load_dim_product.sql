BEGIN;

-- Step 1: Close changed current product versions
UPDATE dwh.dim_product AS target
SET
    valid_to = CURRENT_DATE - 1,
    is_current = FALSE
FROM (
    SELECT DISTINCT ON (TRIM(product_id))
        TRIM(product_id) AS product_id,
        TRIM(name) AS name,
        TRIM(category) AS category,
        TRIM(unit) AS unit
    FROM staging.products
    WHERE product_id IS NOT NULL
      AND TRIM(product_id) <> ''
    ORDER BY TRIM(product_id)
) AS source
WHERE target.product_id = source.product_id
  AND target.is_current = TRUE
  AND (
      LOWER(TRIM(target.name)) IS DISTINCT FROM LOWER(source.name)
      OR LOWER(TRIM(target.category)) IS DISTINCT FROM LOWER(source.category)
      OR LOWER(TRIM(target.unit)) IS DISTINCT FROM LOWER(source.unit)
  );

-- Step 2: Insert products without a current version
INSERT INTO dwh.dim_product (
    product_id,
    name,
    category,
    unit,
    valid_from,
    valid_to,
    is_current
)
SELECT
    source.product_id,
    source.name,
    source.category,
    source.unit,
    CURRENT_DATE,
    NULL,
    TRUE
FROM (
    SELECT DISTINCT ON (TRIM(product_id))
        TRIM(product_id) AS product_id,
        TRIM(name) AS name,
        TRIM(category) AS category,
        TRIM(unit) AS unit
    FROM staging.products
    WHERE product_id IS NOT NULL
      AND TRIM(product_id) <> ''
    ORDER BY TRIM(product_id)
) AS source
WHERE NOT EXISTS (
    SELECT 1
    FROM dwh.dim_product AS target
    WHERE target.product_id = source.product_id
      AND target.is_current = TRUE
);

COMMIT;