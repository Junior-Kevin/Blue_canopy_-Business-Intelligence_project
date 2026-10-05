USE Blue_canopy;
GO
DROP TABLE IF EXISTS silver.pos_line_items;
GO
WITH base AS (
    SELECT
        REPLACE(TRIM([transaction_id]),' ' ,'') AS transaction_id,  -- Remove spaces
        [line_number],
        CASE
		     WHEN [product_id] LIKE '%DUP' THEN SUBSTRING(product_id,1,CHARINDEX('D',product_id,5)-2)
			 ELSE [product_id] END AS product_id,
        ABS(CAST([quantity] AS INT)) AS quantity,
        ROUND(ABS(CAST([unit_price] AS FLOAT)), 2) AS unit_price_kes,
        ABS(CAST([discount_rate] AS FLOAT)) AS discount_rate,
		CASE WHEN line_total LIKE 'CMP%' THEN LEFT(line_total,8)
	        ELSE '' END campaign,
        ABS(CAST(CASE
	       WHEN TRIM(REPLACE([line_total],',',''))  LIKE 'CMP%'
		   THEN SUBSTRING(TRIM(REPLACE([line_total],',','')),
		        9,20)
			ELSE TRIM(REPLACE([line_total],',',''))
		END AS FLOAT)) line_total
    FROM [Blue_canopy].[bronze].[pos_line_items_raw]
    WHERE [transaction_id] IS NOT NULL 
      AND [transaction_id] != ''
      AND [product_id] IS NOT NULL
),
validated AS (
    SELECT 
        -- Core identifiers
        transaction_id,
        line_number,
        product_id,
        
        -- Quantities and pricing
        quantity,
        unit_price_kes,
        discount_rate,
        line_total,
        
        -- Calculate expected line total (validation)
        ROUND(quantity * unit_price_kes * (1 - discount_rate), 2) AS calculated_line_total,
        
        -- Calculate discount amount
        ROUND(quantity * unit_price_kes * discount_rate, 2) AS discount_amount_kes,
        
        -- Calculate unit price after discount
        ROUND(unit_price_kes * (1 - discount_rate), 2) AS effective_unit_price_kes,
        
        -- Discount tier categorization
        CASE 
            WHEN discount_rate = 0 THEN 'No Discount'
            WHEN discount_rate < 0.05 THEN 'Small Discount (<5%)'
            WHEN discount_rate < 0.10 THEN 'Standard Discount (5-10%)'
            WHEN discount_rate < 0.20 THEN 'Large Discount (10-20%)'
            ELSE 'Heavy Discount (>20%)'
        END AS discount_tier,
        
        -- Line value tier
        CASE 
            WHEN line_total >= 500000 THEN 'Premium Line (500K+ KES)'
            WHEN line_total >= 100000 THEN 'High Value Line (100K-500K)'
            WHEN line_total >= 50000 THEN 'Medium Value Line (50K-100K)'
            WHEN line_total >= 10000 THEN 'Low Value Line (10K-50K)'
            ELSE 'Small Item (<10K KES)'
        END AS line_value_tier,
        
        -- Extract transaction prefix and sequence
        CASE 
            WHEN transaction_id LIKE 'TXN-%' THEN 'POS'
            WHEN transaction_id LIKE '%-%' THEN LEFT(transaction_id, CHARINDEX('-', transaction_id) - 1)
            ELSE 'Unknown'
        END AS transaction_source,
        
        -- Data quality flag
        CASE 
            WHEN quantity <= 0 THEN 'Invalid quantity'
            WHEN unit_price_kes <= 0 THEN 'Invalid unit price'
            WHEN discount_rate < 0 OR discount_rate > 1 THEN 'Invalid discount rate'
            WHEN line_total <= 0 THEN 'Invalid line total'
            WHEN ABS(ROUND(quantity * unit_price_kes * (1 - discount_rate), 2) - line_total) > 0.01 THEN 'Line total mismatch'
            WHEN transaction_id LIKE '% %' OR transaction_id = '' THEN 'Malformed transaction ID'
            ELSE 'Valid'
        END AS quality_flag
        
    FROM base
),
-- Aggregate duplicate products within the same transaction
aggregated AS (
    SELECT 
        transaction_id,
        product_id,
        MIN(line_number) AS line_number,  -- Keep the first line number
        SUM(quantity) AS quantity,
        AVG(unit_price_kes) AS unit_price_kes,  -- Assuming same price, use AVG
        AVG(discount_rate) AS discount_rate,    -- Assuming same discount rate, use AVG
        SUM(line_total) AS line_total,
        SUM(ROUND(quantity * unit_price_kes * discount_rate, 2)) AS discount_amount_kes,
        -- Weighted average for effective unit price
        ROUND(SUM(quantity * unit_price_kes * (1 - discount_rate)) / SUM(quantity), 2) AS effective_unit_price_kes,
        -- Handle discount_tier: if all same, keep it; otherwise use 'Mixed'
        CASE 
            WHEN COUNT(DISTINCT 
                CASE 
                    WHEN discount_rate = 0 THEN 'No Discount'
                    WHEN discount_rate < 0.05 THEN 'Small Discount (<5%)'
                    WHEN discount_rate < 0.10 THEN 'Standard Discount (5-10%)'
                    WHEN discount_rate < 0.20 THEN 'Large Discount (10-20%)'
                    ELSE 'Heavy Discount (>20%)'
                END
            ) = 1 
            THEN MAX(
                CASE 
                    WHEN discount_rate = 0 THEN 'No Discount'
                    WHEN discount_rate < 0.05 THEN 'Small Discount (<5%)'
                    WHEN discount_rate < 0.10 THEN 'Standard Discount (5-10%)'
                    WHEN discount_rate < 0.20 THEN 'Large Discount (10-20%)'
                    ELSE 'Heavy Discount (>20%)'
                END
            )
            ELSE 'Mixed Discount Tiers'
        END AS discount_tier,
        -- Recalculate line_value_tier based on aggregated line_total
        CASE 
            WHEN SUM(line_total) >= 500000 THEN 'Premium Line (500K+ KES)'
            WHEN SUM(line_total) >= 100000 THEN 'High Value Line (100K-500K)'
            WHEN SUM(line_total) >= 50000 THEN 'Medium Value Line (50K-100K)'
            WHEN SUM(line_total) >= 10000 THEN 'Low Value Line (10K-50K)'
            ELSE 'Small Item (<10K KES)'
        END AS line_value_tier,
        MAX(transaction_source) AS transaction_source
    FROM validated
    WHERE quality_flag = 'Valid'
    GROUP BY transaction_id, product_id
)

SELECT 
    -- Surrogate key
    ROW_NUMBER() OVER(ORDER BY transaction_id, line_number) AS pos_line_key,
    -- Foreign keys
    transaction_id,
    line_number,
    product_id,
    -- Quantities and pricing
    quantity,
    ROUND(unit_price_kes, 2) AS unit_price_kes,
    ROUND(discount_rate, 2) AS discount_rate,
    ROUND(effective_unit_price_kes, 2) AS effective_unit_price_kes,
    ROUND(discount_amount_kes, 2) AS discount_amount_kes,
    ROUND(line_total, 2) AS line_total,
    -- Categorizations
    discount_tier,
    line_value_tier,
    transaction_source,
    -- Audit
    GETDATE() AS etl_load_date,
    'silver.pos_line_items' AS etl_source
INTO silver.pos_line_items
FROM aggregated
ORDER BY transaction_id, line_number;

DROP INDEX IF EXISTS idx_pos_line_items_poslinekey ON silver.pos_line_items;

CREATE CLUSTERED COLUMNSTORE INDEX idx_pos_line_items_poslinekey ON
silver.pos_line_items;

DROP INDEX IF EXISTS idx_poslineitemstransaction_id ON silver.pos_line_items;

CREATE NONCLUSTERED INDEX idx_poslineitemstransaction_id 
ON silver.pos_line_items (transaction_id);
