-- 45_basket_weights.sql
-- Owner: R3 (Warehouse & SQL Lead)
-- Basket of the price index (checklist section 11): a fixed list of 10-20
-- staple products with predefined weights. serving.v_basket_index reads it.
-- NEW TABLE NAME: not in checklist section 6, announced to the team in the PR.
--
-- Weights should add up to 1 (e.g. 0.10 = 10%). The view divides every weight by
-- the total, so relative weights (3 and 2) give the same index as 0.6 and 0.4.
-- The table is EMPTY until the real basket is chosen: with no rows the index
-- view returns no rows. Example:
--   INSERT INTO dwh.basket_weights VALUES ('<product_id from the scraper>', 0.10);

SET ROLE etl_user;

CREATE TABLE IF NOT EXISTS dwh.basket_weights (
    product_id  TEXT PRIMARY KEY,                 -- stable id, same as dwh.dim_product.product_id
    weight      NUMERIC(8,6) NOT NULL CHECK (weight > 0)
);

RESET ROLE;