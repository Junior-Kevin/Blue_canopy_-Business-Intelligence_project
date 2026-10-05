WITH base AS (
    SELECT 
        [county]
        -- Fix date conversion
        ,DATEFROMPARTS(
            CAST(LEFT([year_month], 4) AS INT), 
            CAST(RIGHT([year_month], 2) AS INT), 
            1
        ) AS month_start_date
        ,EOMONTH(DATEFROMPARTS(
            CAST(LEFT([year_month], 4) AS INT), 
            CAST(RIGHT([year_month], 2) AS INT), 
            1
        )) AS date
        -- Numeric conversions
        ,CAST([gdp_growth_pct] AS FLOAT) AS gdp_growth_pct
        ,CAST([inflation_pct] AS FLOAT) AS inflation_pct
        ,CAST([unemployment_pct] AS FLOAT) AS unemployment_pct
        ,CAST([consumer_confidence] AS FLOAT) AS consumer_confidence
        ,CAST([retail_sales_index] AS FLOAT) AS retail_sales_index
        ,CAST([fuel_price_kes] AS FLOAT) AS fuel_price_kes
        ,CAST([usd_kes_rate] AS FLOAT) AS usd_kes_rate
    FROM [Blue_canopy].[bronze].[economic_raw]
)

SELECT 
    -- Surrogate Key
    CONCAT([county], '_', FORMAT([date], 'yyyyMM')) AS economic_id
    
    -- Dimensions
    ,[county]
    ,[date]
    ,[month_start_date]
    
    -- Time hierarchies
    ,YEAR([date]) AS calendar_year
    ,MONTH([date]) AS calendar_month
    ,DATEPART(QUARTER, [date]) AS calendar_quarter
    ,CONCAT('Q', DATEPART(QUARTER, [date]), ' ', YEAR([date])) AS quarter_label
    ,FORMAT([date], 'MMMM') AS month_name
    
    -- Measures
    ,[gdp_growth_pct]
    ,[inflation_pct]
    ,[unemployment_pct]
    ,[consumer_confidence]
    ,[retail_sales_index]
    ,[fuel_price_kes]
    ,[usd_kes_rate]
    
    -- Derived Metrics
    -- Real retail sales (inflation-adjusted)
    ,ROUND([retail_sales_index] * (100 / (100 + [inflation_pct])), 2) AS real_retail_sales_index
    
    -- Economic health composite (0-100 scale)
    ,ROUND(
        (100 - [unemployment_pct]) * 0.4 + 
        [consumer_confidence] * 0.3 + 
        (CASE WHEN [gdp_growth_pct] > 0 THEN 50 + [gdp_growth_pct] * 5 ELSE 50 + [gdp_growth_pct] * 5 END) * 0.3
    , 2) AS economic_health_score
    
    -- Data Quality
    ,CASE 
        WHEN [gdp_growth_pct] IS NULL THEN 'Missing GDP'
        WHEN [inflation_pct] < 0 OR [inflation_pct] > 50 THEN 'Invalid inflation'
        WHEN [unemployment_pct] < 0 OR [unemployment_pct] > 100 THEN 'Invalid unemployment'
        WHEN [consumer_confidence] < 0 OR [consumer_confidence] > 100 THEN 'Invalid confidence'
        WHEN [retail_sales_index] < 0 THEN 'Invalid retail index'
        WHEN [fuel_price_kes] <= 0 THEN 'Invalid fuel price'
        WHEN [usd_kes_rate] <= 0 THEN 'Invalid exchange rate'
        ELSE 'Valid'
    END AS quality_flag
    
    -- Outlier Flags
    ,CASE 
        WHEN [gdp_growth_pct] > 10 THEN 'High Growth Alert'
        WHEN [gdp_growth_pct] < -5 THEN 'Recession Alert'
        WHEN [inflation_pct] > 20 THEN 'Hyperinflation Alert'
        WHEN [usd_kes_rate] > 200 THEN 'Currency Crisis Alert'
        ELSE 'Normal Range'
    END AS outlier_flag
    
    -- Audit Columns
    ,GETDATE() AS etl_load_date
    ,'silver.economic' AS etl_source
    
INTO silver.economic
FROM base
WHERE [date] IS NOT NULL  -- Filter out invalid dates
