-- 65_serving_fx_gold.sql
-- Owner: R1 wrote it (tasks 6.4 + 6.5), R3 reviews + merges (R3 owns sql/*).
-- Dollar and gold analysis for the dashboard. Views only, like 60_serving.sql.
-- Rates are EGP per 1 USD (currency) and EGP per GRAM (gold, karat 24/21/18).
--
-- IMPORTANT: correlation is NOT causation. With ~30 days of data it only
-- describes whether two series moved together in this short window.

SET ROLE etl_user;

-- Daily rate of every currency / gold karat with day-over-day change.
CREATE OR REPLACE VIEW serving.v_fx_gold_daily AS
SELECT s.source_name AS source,
       c.code,
       c.kind,
       c.karat,
       d.full_date   AS rate_date,
       f.rate,
       f.rate / NULLIF(LAG(f.rate) OVER (
           PARTITION BY f.currency_key, f.source_key
           ORDER BY d.full_date), 0) - 1 AS pct_change
FROM dwh.fact_gold_fx f
JOIN dwh.dim_currency c ON c.currency_key = f.currency_key
JOIN dwh.dim_source   s ON s.source_key   = f.source_key
JOIN dwh.dim_date     d ON d.date_key     = f.date_key;

-- Basket index next to USD and 21-karat gold, with each one's daily change.
CREATE OR REPLACE VIEW serving.v_fx_gold_vs_index AS
WITH usd AS (
    SELECT rate_date, rate AS usd_egp
    FROM serving.v_fx_gold_daily
    WHERE code = 'USD' AND kind = 'currency'
),
gold AS (
    SELECT rate_date, rate AS gold21_egp_per_gram
    FROM serving.v_fx_gold_daily
    WHERE code = 'XAU' AND kind = 'gold' AND karat = 21
),
joined AS (
    SELECT i.index_date, i.index_value, u.usd_egp, g.gold21_egp_per_gram
    FROM serving.v_basket_index i
    LEFT JOIN usd  u ON u.rate_date = i.index_date
    LEFT JOIN gold g ON g.rate_date = i.index_date
)
SELECT index_date,
       index_value,
       usd_egp,
       gold21_egp_per_gram,
       index_value / NULLIF(LAG(index_value) OVER w, 0) - 1 AS index_pct_change,
       usd_egp / NULLIF(LAG(usd_egp) OVER w, 0) - 1          AS usd_pct_change,
       gold21_egp_per_gram / NULLIF(LAG(gold21_egp_per_gram) OVER w, 0) - 1
                                                              AS gold21_pct_change
FROM joined
WINDOW w AS (ORDER BY index_date);

-- One-row summary: correlation of DAILY CHANGES (not levels, which mislead).
CREATE OR REPLACE VIEW serving.v_fx_gold_index_correlation AS
SELECT COUNT(*) FILTER (WHERE usd_pct_change IS NOT NULL
                          AND index_pct_change IS NOT NULL)    AS n_days_usd,
       CORR(usd_pct_change, index_pct_change)                  AS corr_usd_vs_index,
       COUNT(*) FILTER (WHERE gold21_pct_change IS NOT NULL
                          AND index_pct_change IS NOT NULL)    AS n_days_gold,
       CORR(gold21_pct_change, index_pct_change)               AS corr_gold21_vs_index,
       'Correlation is not causation; short window, indicative only.' AS note
FROM serving.v_fx_gold_vs_index;

RESET ROLE;
