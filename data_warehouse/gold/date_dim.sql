-- Create gold schema
-- Create universal date dimension (critical for all marts)
WITH dates AS (
    SELECT DISTINCT date FROM (
        SELECT start_date AS date FROM silver.campaigns UNION
        SELECT registration_date FROM silver.crm UNION
        SELECT order_date FROM silver.ecommerce_orders UNION
        SELECT date FROM silver.economic UNION
        SELECT feedback_date FROM silver.feedback UNION
        SELECT transaction_date FROM silver.gl_transactions UNION
        SELECT receipt_date FROM silver.goods_receipts UNION
        SELECT movement_date FROM silver.inventory_movements UNION
        SELECT snapshot_date FROM silver.inventory_snapshots UNION
        SELECT transaction_date FROM silver.loyalty_transactions UNION
        SELECT date FROM silver.pos_transactions UNION
        SELECT return_date FROM silver.returns UNION
        SELECT interaction_date FROM silver.service_interactions
    ) AS all_dates
)
SELECT 
    -- ===== IDENTIFIER =====
    date_id = CONVERT(INT, FORMAT(date, 'yyyyMMdd')),
    date,
    
    -- ===== DAY LEVEL =====
    day_of_week = DATEPART(weekday, date),        -- 1-7
    day_name = DATENAME(weekday, date),           -- Full name
    day_name_short = FORMAT(date, 'ddd'),         -- 3-letter abbrev
    day_of_month = DAY(date),                     -- 1-31
    day_of_the_year = DATEPART(dayofyear, date),  -- 1-366
    
    -- ===== WEEK LEVEL =====
    week_of_year = DATEPART(week, date),          -- 1-53
    
    -- ===== MONTH LEVEL =====
    month = MONTH(date),                          -- 1-12
    month_name = DATENAME(MONTH, date),           -- Full name
    month_name_short = FORMAT(date, 'MMM'),       -- 3-letter abbrev
    year_month = DATETRUNC(MONTH, date),          -- First day of month
    
    -- ===== QUARTER LEVEL =====
    quarter = DATEPART(quarter, date),            -- 1-4
    quarter_name = 'Q' + CAST(DATEPART(quarter, date) AS VARCHAR) + ' ' + CAST(YEAR(date) AS VARCHAR),
    
    -- ===== YEAR LEVEL =====
    year = YEAR(date),
    
    -- ===== FISCAL =====
    fiscal_year = CONCAT(YEAR(DATEADD(month, -6, date)), '/', YEAR(DATEADD(month, 6, date))),
    fiscal_quarter = DATEPART(quarter, DATEADD(month, -6, date)),
    
    -- ===== FLAGS =====
    is_weekend = CASE WHEN DATEPART(weekday, date) IN (1, 7) THEN 'yes' ELSE 'no' END
INTO gold.dim_date
FROM dates
ORDER BY date;

