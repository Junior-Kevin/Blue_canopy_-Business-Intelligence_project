DROP TABLE IF EXISTS silver.goods_receipts;
GO
WITH base AS (
    SELECT 
        [receipt_id],
        [po_number],
		CAST (CASE 
		    WHEN receipt_date= '2023-13-45' THEN '2023-12-25'
			ELSE receipt_date
		END AS DATE)  receipt_date, 
        [product_id],
        CAST([quantity_received] AS INT) AS quantity_received,
        [receiving_notes]
    FROM [Blue_canopy].[bronze].[goods_receipts_raw]
    WHERE [receipt_id] IS NOT NULL 
        AND [po_number] IS NOT NULL
),

cleaned AS (
    SELECT 
        -- Core identifiers
        receipt_id,
        po_number,
        product_id,
        
        -- Clean po_number (ensure consistency)
        UPPER(TRIM(po_number)) AS po_number_clean,
        
        -- Receipt date
        receipt_date,
        YEAR(receipt_date) AS receipt_year,
        MONTH(receipt_date) AS receipt_month,
        DATEPART(QUARTER, receipt_date) AS receipt_quarter,
        FORMAT(receipt_date, 'yyyy-MM') AS receipt_year_month,
        
        -- Quantity
        quantity_received,
        
        -- Receiving notes (standardize)
        COALESCE(
            CASE 
                WHEN receiving_notes = 'NULL' THEN NULL
                ELSE receiving_notes
            END, 
            'No issues recorded'
        ) AS receiving_notes_clean,
        
        -- Categorize receipt quality
        CASE 
            WHEN receiving_notes LIKE '%Damaged%' THEN 'Damaged Goods'
            WHEN receiving_notes LIKE '%Wrong%' THEN 'Wrong Items'
            WHEN receiving_notes LIKE '%OK%' THEN 'Good Condition'
            WHEN receiving_notes IS NULL OR receiving_notes = 'NULL' THEN 'No Issues Recorded'
            ELSE 'Other Issue'
        END AS receipt_quality_category,
        
        -- Flag for problematic receipts
        CASE 
            WHEN receiving_notes IN ('Damaged in transit', 'Wrong items', 'Shortage') THEN 1
            ELSE 0
        END AS has_quality_issue,
        
        -- Data quality
        CASE 
            WHEN quantity_received <= 0 THEN 'Invalid quantity'
            WHEN receipt_date > GETDATE() THEN 'Future receipt date'
            WHEN receipt_date < '2015-01-01' THEN 'Suspicious old date'
            WHEN product_id IS NULL THEN 'Missing product'
            ELSE 'Valid'
        END AS quality_flag
        
    FROM base
)

SELECT 
    -- Surrogate key
    receipt_id AS receipt_key,
    
    -- Identifiers
    receipt_id,
    po_number_clean AS po_number,
    product_id,
    
    -- Receipt details
    receipt_date,
    quantity_received,
    receiving_notes_clean AS receiving_notes,
    receipt_quality_category,
    has_quality_issue,
    
    -- Time attributes
    receipt_year,
    receipt_month,
    receipt_quarter,
    receipt_year_month,
    
    -- Quality
    quality_flag,
    
    -- Audit
    GETDATE() AS etl_load_date,
    'silver.goods_receipts' AS etl_source
    
INTO silver.goods_receipts
FROM cleaned
WHERE quantity_received > 0
ORDER BY receipt_date DESC, po_number
