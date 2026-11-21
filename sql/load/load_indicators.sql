-- load_indicators.sql   (R3, tasks 4.1 / 4.4 / 4.8)
-- Sources: world_bank, official_file.  staging.indicators_clean -> dwh.dim_indicator + dwh.fact_indicator
-- ONE transaction: dimension first, then facts. Safe to run many times.
-- Annual data has period_month NULL in staging and 0 in dwh (it is part of the primary key).
-- A NULL value (gap in the source) is kept as NULL, never filled.

BEGIN;

INSERT INTO dwh.dim_indicator (indicator_code, indicator_name, unit, frequency)
SELECT DISTINCT ON (TRIM(indicator_code))
       TRIM(indicator_code), indicator_name, unit, frequency
FROM staging.indicators_clean
WHERE indicator_code IS NOT NULL AND TRIM(indicator_code) <> ''
ORDER BY TRIM(indicator_code), period_year DESC, period_month DESC NULLS LAST
ON CONFLICT (indicator_code)
DO UPDATE SET indicator_name = EXCLUDED.indicator_name,
              unit           = EXCLUDED.unit,
              frequency      = EXCLUDED.frequency;

INSERT INTO dwh.fact_indicator (indicator_key, source_key, country, period_year, period_month, value)
SELECT DISTINCT ON (i.indicator_key, src.source_key, s.country, s.period_year, COALESCE(s.period_month, 0))
       i.indicator_key, src.source_key, s.country, s.period_year, COALESCE(s.period_month, 0), s.value
FROM staging.indicators_clean s
JOIN dwh.dim_indicator i ON i.indicator_code = TRIM(s.indicator_code)
JOIN dwh.dim_source  src ON src.source_name  = s.source
WHERE s.country IS NOT NULL AND s.period_year IS NOT NULL
ORDER BY i.indicator_key, src.source_key, s.country, s.period_year, COALESCE(s.period_month, 0)
ON CONFLICT (indicator_key, source_key, country, period_year, period_month)
DO UPDATE SET value     = EXCLUDED.value,
              loaded_at = now();

COMMIT;