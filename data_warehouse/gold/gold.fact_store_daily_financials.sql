USE Blue_canopy;
GO

-- ============================================================
-- GOLD: gold.fact_store_daily_financials
-- Grain: one row per store per day.
-- Measures: sales, COGS, gross margin, operating expenses, net profit.
-- ============================================================

DROP TABLE IF EXISTS gold.fact_store_daily_financials;
GO

SELECT
    -- Surrogate key
    CONVERT(INT, ROW_NUMBER() OVER (
        ORDER BY sdf.date, sdf.store_id
    )) AS store_daily_financial_sk,

    -- Foreign keys
    ISNULL(ds.store_key, -1) AS store_key,
    sdf.date                 AS financial_date,

    -- Measures (already aggregated in Silver)
    sdf.sales_kes,
    sdf.cost_of_goods_sold,
    sdf.gross_margin,
    sdf.operating_expenses,
    sdf.net_profit,

    -- Derived ratios (materialized for fast reporting)
    CAST(
        CASE WHEN sdf.sales_kes = 0 THEN 0
             ELSE sdf.gross_margin * 100.0 / sdf.sales_kes
        END AS DECIMAL(9,2)
    ) AS gross_margin_pct,
    CAST(
        CASE WHEN sdf.sales_kes = 0 THEN 0
             ELSE sdf.net_profit * 100.0 / sdf.sales_kes
        END AS DECIMAL(9,2)
    ) AS net_profit_pct,

    -- Audit
    GETDATE() AS etl_load_date,
    'gold.fact_store_daily_financials' AS etl_source

INTO gold.fact_store_daily_financials
FROM silver.store_daily_financials sdf
LEFT JOIN gold.dim_store_bridge ds
    ON sdf.store_id = ds.store_id;
GO

CREATE NONCLUSTERED INDEX idx_fsdf_date
    ON gold.fact_store_daily_financials (financial_date);
GO

CREATE NONCLUSTERED INDEX idx_fsdf_store
    ON gold.fact_store_daily_financials (store_key);
GO
