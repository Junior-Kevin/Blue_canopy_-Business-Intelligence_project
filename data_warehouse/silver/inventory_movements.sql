WITH base AS (
    SELECT 
        [movement_id]
        ,CAST(
            CASE 
                WHEN [movement_date] = '2023-13-45' THEN '2022-10-15'
                ELSE [movement_date] 
            END AS DATE
        ) AS movement_date
        ,[store_id]
        ,[product_id]
        ,[movement_type]
        ,CAST([quantity] AS FLOAT) AS quantity  -- Keep as FLOAT for calculations
        ,CAST([unit_cost_kes] AS FLOAT) AS unit_cost_kes  -- Convert to FLOAT as well
    FROM [Blue_canopy].[bronze].[inventory_movements_raw]
    WHERE [movement_date] IS NOT NULL 
        AND [movement_id] NOT LIKE '%DUP'
),

cleaned AS (
    SELECT 
        -- Core fields
        movement_id
        ,movement_date
        
        -- Cleaned dimensions
        ,CASE 
            WHEN store_id LIKE '%-DUP%' THEN LEFT(store_id, CHARINDEX('-DUP', store_id) - 1)
            ELSE store_id
        END AS store_id_clean
        ,product_id
        ,movement_type
        
        -- Absolute quantity for calculations
        ,ABS(quantity) AS quantity_absolute
        ,quantity AS quantity_raw
        ,CASE 
            WHEN movement_type IN ('SALE', 'TRANSFER_OUT', 'ADJUSTMENT_OUT') THEN -ABS(quantity)
            ELSE ABS(quantity)
        END AS quantity_signed
        ,unit_cost_kes
        
        -- Derived values
        ,ROUND(ABS(quantity) * unit_cost_kes, 2) AS movement_value_kes
        
        -- Time hierarchies
        ,YEAR(movement_date) AS movement_year
        ,MONTH(movement_date) AS movement_month
        ,DATEPART(QUARTER, movement_date) AS movement_quarter
        ,FORMAT(movement_date, 'yyyy-MM') AS movement_year_month
        ,FORMAT(movement_date, 'MMMM') AS movement_month_name
        
        -- Validate sign consistency
        ,CASE 
            WHEN movement_type IN ('SALE', 'TRANSFER_OUT', 'ADJUSTMENT_OUT') AND quantity > 0 
                THEN 'Positive quantity for outbound'
            WHEN movement_type IN ('RECEIPT', 'TRANSFER_IN', 'ADJUSTMENT_IN', 'RETURN') AND quantity < 0 
                THEN 'Negative quantity for inbound'
            ELSE 'Valid sign'
        END AS sign_validation_flag
        
    FROM base
),

with_running AS (
    SELECT 
        *,
        -- Running inventory (per product-store) - for stock levels
        SUM(quantity_signed) OVER (
            PARTITION BY product_id, store_id_clean 
            ORDER BY movement_date, movement_id
            ROWS UNBOUNDED PRECEDING
        ) AS running_quantity,
        
        -- Cumulative sum by product only (across all stores)
        SUM(quantity_signed) OVER (
            PARTITION BY product_id 
            ORDER BY movement_date, movement_id
            ROWS UNBOUNDED PRECEDING
        ) AS cumulative_sum_by_product,
        
        -- Cumulative sum by product-store (more detailed)
        SUM(quantity_signed) OVER (
            PARTITION BY product_id, store_id_clean 
            ORDER BY movement_date, movement_id
            ROWS UNBOUNDED PRECEDING
        ) AS cumulative_sum_by_product_store,
        
        -- Running total of quantity (raw, without sign consideration) - Cast to handle decimals
        SUM(CAST(quantity_raw AS FLOAT)) OVER (
            PARTITION BY product_id 
            ORDER BY movement_date, movement_id
            ROWS UNBOUNDED PRECEDING
        ) AS running_total_raw_quantity,
        
        -- Moving sum of last 3 transactions per product
        SUM(quantity_signed) OVER (
            PARTITION BY product_id 
            ORDER BY movement_date, movement_id
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ) AS moving_sum_3_transactions
        
    FROM cleaned
)

SELECT 
    -- Surrogate key
    CONCAT(movement_id, '_', FORMAT(movement_date, 'yyyyMMdd')) AS inventory_movement_key
    
    -- Dimensions
    ,movement_id
    ,movement_date
    ,store_id_clean AS store_id
    ,product_id
    ,movement_type
    
    -- Quantities (rounded for cleaner output)
    ,ROUND(quantity_signed, 2) AS quantity
    ,ROUND(quantity_absolute, 2) AS quantity_absolute
    ,ROUND(unit_cost_kes, 2) AS unit_cost_kes
    
    -- Financial
    ,ROUND(movement_value_kes, 2) AS movement_value_kes
    
    -- Inventory context (rounded)
    ,ROUND(running_quantity, 2) AS running_quantity
    ,ROUND(cumulative_sum_by_product, 2) AS cumulative_sum_by_product
    ,ROUND(cumulative_sum_by_product_store, 2) AS cumulative_sum_by_product_store
    ,ROUND(running_total_raw_quantity, 2) AS running_total_raw_quantity
    ,ROUND(moving_sum_3_transactions, 2) AS moving_sum_3_transactions
    
    -- Inventory status flags (using FLOAT comparisons)
    ,CASE 
        WHEN running_quantity < 0 THEN 'Negative stock alert'
        WHEN running_quantity = 0 THEN 'Zero stock'
        WHEN running_quantity BETWEEN 1 AND 50 THEN 'Low stock'
        WHEN running_quantity BETWEEN 51 AND 200 THEN 'Adequate stock'
        WHEN running_quantity > 200 THEN 'Excess stock'
        ELSE 'Unknown'
    END AS inventory_status
    
    -- Demand velocity (based on moving sum)
    ,CASE 
        WHEN moving_sum_3_transactions > 100 THEN 'High demand - Reorder now'
        WHEN moving_sum_3_transactions BETWEEN 30 AND 100 THEN 'Normal demand'
        WHEN moving_sum_3_transactions BETWEEN 1 AND 29 THEN 'Low demand - Reduce stock'
        WHEN moving_sum_3_transactions = 0 THEN 'No recent activity'
        ELSE 'Insufficient data'
    END AS demand_velocity
    
    -- Time attributes
    ,movement_year
    ,movement_month
    ,movement_quarter
    ,movement_year_month
    ,movement_month_name
    
    -- Data Quality
    ,sign_validation_flag
    ,CASE 
        WHEN movement_id IS NULL THEN 'Missing movement ID'
        WHEN store_id_clean IS NULL OR store_id_clean = '' THEN 'Missing store'
        WHEN product_id IS NULL OR product_id = '' THEN 'Missing product'
        WHEN movement_type NOT IN ('SALE', 'RECEIPT', 'TRANSFER_IN', 'TRANSFER_OUT', 'ADJUSTMENT_IN', 'ADJUSTMENT_OUT', 'RETURN') 
            THEN 'Invalid movement type'
        WHEN quantity_absolute IS NULL OR quantity_absolute = 0 THEN 'Zero/null quantity'
        WHEN unit_cost_kes IS NULL OR unit_cost_kes <= 0 THEN 'Invalid unit cost'
        WHEN running_quantity < 0 THEN 'Negative inventory'
        ELSE 'Valid'
    END AS quality_flag
    
    -- Audit
    ,GETDATE() AS etl_load_date
    ,'silver.inventory_movements' AS etl_source
    
INTO silver.inventory_movements  -- Uncomment when ready to create table
FROM with_running
WHERE movement_date IS NOT NULL
ORDER BY product_id, movement_date
