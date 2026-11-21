# Warehouse ERD (schema `dwh`)

Star schema of the Egypt Economic Intelligence Platform. Dimensions are loaded first, then facts.
`dim_product` is SCD Type 2: every change of name/category/unit creates a new row (`product_key`) while `product_id` stays the same, and only one row per product has `is_current = true`.
Names follow the DDL in `sql/40_dwh.sql` exactly.

```mermaid
erDiagram
    DIM_DATE ||--o{ FACT_PRICE : "has"
    DIM_SOURCE ||--o{ FACT_PRICE : "provides"
    DIM_PRODUCT ||--o{ FACT_PRICE : "priced_as"

    DIM_DATE ||--o{ FACT_GOLD_FX : "has"
    DIM_SOURCE ||--o{ FACT_GOLD_FX : "provides"
    DIM_CURRENCY ||--o{ FACT_GOLD_FX : "priced_as"

    DIM_SOURCE ||--o{ FACT_INDICATOR : "provides"
    DIM_INDICATOR ||--o{ FACT_INDICATOR : "describes"

    DIM_DATE {
        int date_key PK
        date full_date UK
        smallint day_of_month
        smallint day_of_week
        smallint week_of_year
        smallint month
        string month_name
        smallint quarter
        smallint year
    }

    DIM_SOURCE {
        int source_key PK
        string source_name UK
        string source_type
    }

    DIM_PRODUCT {
        int product_key PK
        string product_id
        string name
        string category
        string unit
        date valid_from
        date valid_to
        boolean is_current
    }

    DIM_CURRENCY {
        int currency_key PK
        string code
        string kind
        smallint karat
    }

    DIM_INDICATOR {
        int indicator_key PK
        string indicator_code UK
        string indicator_name
        string unit
        string frequency
    }

    FACT_PRICE {
        int product_key PK, FK
        int source_key PK, FK
        int date_key PK, FK
        decimal price
        decimal unit_price
        timestamp loaded_at
    }

    FACT_GOLD_FX {
        int currency_key PK, FK
        int source_key PK, FK
        int date_key PK, FK
        decimal rate
        timestamp loaded_at
    }

    FACT_INDICATOR {
        int indicator_key PK, FK
        int source_key PK, FK
        string country PK
        smallint period_year PK
        smallint period_month PK
        decimal value
        timestamp loaded_at
    }
```

## Notes

- `dim_date.date_key` is `YYYYMMDD` and is pre-filled for 2020-2035.
- `fact_indicator.period_month = 0` means annual data; `value` can be NULL (World Bank has gaps).
- `dim_currency` is unique on `(code, kind, COALESCE(karat, 0))`.
- `dim_product` has a unique partial index on `product_id WHERE is_current`.