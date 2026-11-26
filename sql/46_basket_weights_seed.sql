-- 46_basket_weights_seed.sql
-- Owner: R3 (Warehouse & SQL Lead)
-- The real fixed basket: 15 staple products from docs/sources.md ("Fixed Basket").
-- product_id = the id of the product on the site (same as dwh.dim_product.product_id).
-- Weights are RELATIVE (1 each = equal weights); serving.v_basket_index divides every
-- weight by the total, so the weights always add up to 1 (1/15 each here).
-- Safe to re-run: existing rows are not changed.

SET ROLE etl_user;

INSERT INTO dwh.basket_weights (product_id, weight) VALUES
    ('4613',  1),   -- Rice
    ('6896',  1),   -- Sugar
    ('6565',  1),   -- Flour
    ('4408',  1),   -- Pasta
    ('27685', 1),   -- Lentils
    ('27687', 1),   -- White beans
    ('3513',  1),   -- Fava beans (canned)
    ('9478',  1),   -- Eggs
    ('5522',  1),   -- Tea
    ('6563',  1),   -- Salt
    ('25799', 1),   -- Milk
    ('4226',  1),   -- Tuna
    ('1671',  1),   -- White cheese
    ('33084', 1),   -- Chicken
    ('41062', 1)    -- Ghee
ON CONFLICT (product_id) DO NOTHING;

RESET ROLE;