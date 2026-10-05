DROP TABLE IF EXISTS silver.inventory_snapshots;

WITH base AS (
    SELECT 
        -- Fix date once, reuse it
        CASE 
            WHEN snapshot_date = '2023-13-45' THEN CAST('2023-12-25' AS DATE)
            ELSE TRY_CAST(snapshot_date AS DATE)
        END AS snapshot_date,
        store_id,
        product_id,
        CAST(on_hand_quantity AS INT) AS on_hand_quantity,
        CAST(reorder_point AS FLOAT) AS reorder_point,
        CAST(safety_stock AS INT) AS safety_stock
    FROM [Blue_canopy].[bronze].[inventory_snapshots_raw]
),
cleaned AS (
    SELECT 
        -- Clean store IDs (same pattern as movements table)
        CASE 
            WHEN store_id LIKE '%-DUP%' THEN LEFT(store_id, CHARINDEX('-DUP', store_id) - 1)
            ELSE store_id
        END AS store_id_clean,
        
        -- Core data
        product_id,
        on_hand_quantity,
        reorder_point,
        safety_stock,
        
        -- Date processing (now using the already-fixed date)
        snapshot_date,
        YEAR(snapshot_date) AS snapshot_year,
        MONTH(snapshot_date) AS snapshot_month,
        DATEPART(QUARTER, snapshot_date) AS snapshot_quarter,
        FORMAT(snapshot_date, 'yyyy-MM') AS snapshot_year_month,
        DATENAME(WEEKDAY, snapshot_date) AS snapshot_weekday,
        
        -- Calculated metrics
        on_hand_quantity - reorder_point AS stock_vs_reorder,
        
        CASE 
            WHEN on_hand_quantity <= safety_stock THEN 'CRITICAL'
            WHEN on_hand_quantity <= reorder_point THEN 'WARNING'
            WHEN on_hand_quantity <= reorder_point * 1.2 THEN 'CAUTION'
            ELSE 'HEALTHY'
        END AS stock_status,
        
        CASE 
            WHEN on_hand_quantity <= reorder_point 
            THEN (reorder_point + safety_stock) - on_hand_quantity
            ELSE 0
        END AS suggested_reorder_quantity,
        
        -- Data quality
        CASE 
            WHEN on_hand_quantity < 0 THEN 'Negative stock'
            WHEN reorder_point < 0 THEN 'Invalid reorder point'
            WHEN safety_stock < 0 THEN 'Invalid safety stock'
            WHEN on_hand_quantity <= reorder_point THEN 'Below reorder point'
            ELSE 'Valid'
        END AS quality_flag
    FROM base
    --WHERE snapshot_date IS NOT NULL  -- Ensure we have valid dates
)

SELECT 
    -- Surrogate key
    CONCAT(store_id_clean, '_', product_id, '_', FORMAT(snapshot_date, 'yyyyMMdd')) AS snapshot_key,
    
    -- Dimensions
    store_id_clean AS store_id,
    product_id,
    snapshot_date,
    
    -- Measures
    on_hand_quantity,
    reorder_point,
    safety_stock,
    
    -- Derived metrics
    stock_vs_reorder,
    stock_status,
    suggested_reorder_quantity,
    
    -- Time attributes
    snapshot_year,
    snapshot_month,
    snapshot_quarter,
    snapshot_year_month,
    snapshot_weekday,
    
    -- Quality
    quality_flag
    
INTO silver.inventory_snapshots  
FROM cleaned
ORDER BY snapshot_date DESC, store_id_clean, product_id
