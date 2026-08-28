USE Blue_canopy;
GO
DROP TABLE IF EXISTS silver.ecommerce_order_lines
GO
WITH base AS (
    SELECT 
        [order_id],
        [line_number],
        [product_id],
        CAST([quantity] AS INT) AS quantity,
        ABS(ROUND(CAST([unit_price] AS FLOAT), 2)) AS unit_price_kes,
        ABS(CAST([discount_rate] AS FLOAT)) AS discount_rate,
        ABS(ROUND(CAST([line_total] AS FLOAT), 2)) AS line_total_kes
    FROM [Blue_canopy].[bronze].[ecommerce_order_lines_raw]
    WHERE [order_id] IS NOT NULL 
        AND [product_id] IS NOT NULL
),
validated AS (
    SELECT 
        *,
        
        -- Calculate expected line total (validation)
        ROUND(quantity * unit_price_kes * (1 - discount_rate), 2) AS calculated_line_total,
        
        -- Calculate discount amount
        ROUND(quantity * unit_price_kes * discount_rate, 2) AS discount_amount_kes,
        
        -- Calculate unit price after discount
        ROUND(unit_price_kes * (1 - discount_rate), 2) AS unit_price_after_discount_kes,
        
        -- Extract order prefix and sequence
        LEFT(order_id, 4) AS order_prefix,
        TRY_CAST(RIGHT(order_id, 8) AS INT) AS order_sequence_number,
        
        -- Discount tier categorization
        CASE 
            WHEN discount_rate = 0 THEN 'No Discount'
            WHEN discount_rate < 0.05 THEN 'Small Discount (<5%)'
            WHEN discount_rate < 0.10 THEN 'Standard Discount (5-10%)'
            WHEN discount_rate < 0.20 THEN 'Large Discount (10-20%)'
            ELSE 'Heavy Discount (>20%)'
        END AS discount_tier,
        
        -- Data quality flag
        CASE 
            WHEN quantity <= 0 THEN 'Invalid quantity'
            WHEN unit_price_kes <= 0 THEN 'Invalid unit price'
            WHEN discount_rate < 0 OR discount_rate > 1 THEN 'Invalid discount rate'
            WHEN line_total_kes <= 0 THEN 'Invalid line total'
           -- WHEN ROUND(quantity * unit_price_kes * (1 - discount_rate), 2) != line_total_kes 
                --THEN 'Line total mismatch'
            ELSE 'Valid'
        END AS quality_flag
        
    FROM base
),
-- Aggregate duplicate products within the same order (mirrors the POS pipeline).
-- Without this step, two raw lines with the same order_id + product_id stay
-- as two separate rows instead of being merged.
aggregated AS (
    SELECT
        order_id,
        product_id,
        ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY MIN(line_number)) AS line_number,
        SUM(quantity) AS quantity,
        AVG(unit_price_kes) AS unit_price_kes,               -- assuming same price, use AVG
        AVG(discount_rate) AS discount_rate,                 -- assuming same discount rate, use AVG
        SUM(line_total_kes) AS line_total_kes,
        SUM(ROUND(quantity * unit_price_kes * discount_rate, 2)) AS discount_amount_kes,
        -- weighted average for unit price after discount
        ROUND(SUM(quantity * unit_price_kes * (1 - discount_rate)) / SUM(quantity), 2) AS unit_price_after_discount_kes,
        SUM(calculated_line_total) AS calculated_line_total,
        MAX(order_prefix) AS order_prefix,
        MAX(order_sequence_number) AS order_sequence_number,
        -- keep discount_tier if all matching lines agree, otherwise flag as mixed
        CASE
            WHEN COUNT(DISTINCT discount_tier) = 1 THEN MAX(discount_tier)
            ELSE 'Mixed Discount Tiers'
        END AS discount_tier
    FROM validated
    WHERE quality_flag = 'Valid'
    GROUP BY order_id, product_id
)
SELECT 
    -- Surrogate key
    ROW_NUMBER() OVER(ORDER BY order_id, line_number)  AS order_line_key,
    
    -- Dimensions
    order_id,
    line_number,
    product_id,
    
    -- Quantities and pricing
    quantity,
    ROUND(unit_price_kes, 2) AS unit_price_kes,
    ROUND(discount_rate, 2) AS discount_rate,
    ROUND(unit_price_after_discount_kes, 2) AS unit_price_after_discount_kes,
    ROUND(discount_amount_kes, 2) AS discount_amount_kes,
    ROUND(line_total_kes, 2) AS line_total_kes,
    
    -- Validation
    calculated_line_total,
    
    -- Categorizations
    discount_tier,
    order_prefix,
    order_sequence_number,
    
    -- Audit
    GETDATE() AS etl_load_date,
    'silver.ecommerce_order_lines' AS etl_source
    
INTO silver.ecommerce_order_lines
FROM aggregated
ORDER BY order_id, line_number
