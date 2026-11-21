-- load_fx_gold.sql   (R3, tasks 4.1 / 4.4 / 4.8)
-- Source: fx_gold.  staging.fx_gold_clean -> dwh.dim_currency + dwh.fact_gold_fx
-- ONE transaction: dimension first, then facts. Safe to run many times.

BEGIN;

-- dim_currency is built from the real codes in staging (USD, XAU, ...): nothing invented.
INSERT INTO dwh.dim_currency (code, kind, karat)
SELECT DISTINCT TRIM(code), kind, karat::smallint
FROM staging.fx_gold_clean
WHERE code IS NOT NULL AND TRIM(code) <> '' AND kind IN ('currency', 'gold')
ON CONFLICT (code, kind, COALESCE(karat, 0)) DO NOTHING;

INSERT INTO dwh.fact_gold_fx (currency_key, source_key, date_key, rate)
SELECT DISTINCT ON (c.currency_key, src.source_key, dt.date_key)
       c.currency_key, src.source_key, dt.date_key, s.rate
FROM staging.fx_gold_clean s
JOIN dwh.dim_currency c  ON c.code = TRIM(s.code)
                        AND c.kind = s.kind
                        AND COALESCE(c.karat, 0) = COALESCE(s.karat, 0)
JOIN dwh.dim_source  src ON src.source_name = s.source
JOIN dwh.dim_date    dt  ON dt.full_date = s.rate_date
WHERE s.rate IS NOT NULL
ORDER BY c.currency_key, src.source_key, dt.date_key, s.observed_at DESC NULLS LAST
ON CONFLICT (currency_key, source_key, date_key)
DO UPDATE SET rate      = EXCLUDED.rate,
              loaded_at = now();

COMMIT;