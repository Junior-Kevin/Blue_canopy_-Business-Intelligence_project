DROP TABLE IF EXISTS silver.promotion_products;

WITH base AS (
    SELECT 
        [promotion_id],
        [product_id]
    FROM [Blue_canopy].[bronze].[promotion_products_raw]
    WHERE [promotion_id] IS NOT NULL
),

cleaned AS (
    SELECT 
        -- Core identifiers
        promotion_id,
        product_id,
        
        -- Create composite key for uniqueness
        CONCAT(promotion_id, '_', product_id) AS promotion_product_key,
        
        -- Data quality flags
        CASE 
            WHEN product_id IS NULL OR product_id = '' THEN 'Missing product - Invalid'
            WHEN product_id LIKE '%NULL%' THEN 'NULL value - Invalid'
            ELSE 'Valid'
        END AS quality_flag,
        
        -- Record type categorization
        CASE 
            WHEN product_id IS NULL OR product_id = '' THEN 'Invalid record (no product)'
            ELSE 'Valid product promotion link'
        END AS record_type,
        
        -- Audit info
        GETDATE() AS etl_load_date,
        'silver.promotion_products' AS etl_source
        
    FROM base
)

SELECT 
    -- Surrogate key
    promotion_product_key,
    
    -- Foreign keys
    promotion_id,
    product_id,
    
    -- Metadata
    record_type,
    
    -- Quality
    quality_flag,
    
    -- Audit
    etl_load_date,
    etl_source
    
INTO silver.promotion_products
FROM cleaned
WHERE product_id IS NOT NULL  -- Filter out NULL product_ids
  AND product_id != 'NULL'     -- Filter out string 'NULL'
ORDER BY promotion_id, product_id
