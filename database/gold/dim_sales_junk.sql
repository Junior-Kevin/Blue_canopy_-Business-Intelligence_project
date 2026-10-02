USE Blue_canopy;
GO

-- ============================================================
-- GOLD: gold.dim_sales_junk
-- Junk dimension combining payment_method, order_status,
-- and return_reason. Built from SILVER (not from fact_sales)
-- to avoid a circular dependency.
-- ============================================================

DROP TABLE IF EXISTS Blue_canopy.gold.dim_sales_junk;
GO

WITH payment_methods AS (
    SELECT DISTINCT payment_method 
    FROM [Blue_canopy].[silver].[pos_transactions]
    WHERE payment_method IS NOT NULL
    UNION
    SELECT DISTINCT payment_method 
    FROM [Blue_canopy].[silver].[ecommerce_orders]
    WHERE payment_method IS NOT NULL
),
order_statuses AS (
    SELECT DISTINCT order_status 
    FROM [Blue_canopy].[silver].[ecommerce_orders]
    WHERE order_status IS NOT NULL
    UNION
    SELECT 'delivered'  -- POS transactions are always 'delivered'
),
return_reasons AS (
    SELECT DISTINCT return_reason 
    FROM [Blue_canopy].[silver].[sales_returns]
    WHERE return_reason IS NOT NULL
    UNION
    SELECT NULL  -- ensure a NULL return_reason row exists for non-return sales
),
junk_combinations AS (
    SELECT 
        pm.payment_method,
        os.order_status,
        rr.return_reason
    FROM payment_methods pm
    CROSS JOIN order_statuses os
    CROSS JOIN return_reasons rr
)

SELECT 
    ROW_NUMBER() OVER (
        ORDER BY payment_method, order_status, return_reason
    ) AS sales_junk_key,
    payment_method,
    order_status,
    return_reason
INTO Blue_canopy.gold.dim_sales_junk
FROM junk_combinations;
GO
