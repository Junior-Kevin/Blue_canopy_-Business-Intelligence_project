DROP TABLE IF EXISTS silver.purchase_order_lines;

WITH base AS (
    SELECT 
        [po_number],
        [line_number],
        CASE 
            WHEN [product_id] LIKE '%DUP' THEN LEFT(product_id, CHARINDEX('-', product_id, 6) - 1) 
            ELSE product_id 
        END AS product_id,
        CAST([quantity_ordered] AS INT) AS quantity_ordered,
        ROUND(CAST([unit_price] AS FLOAT), 2) AS unit_price_kes,
        ROUND(CAST([line_total] AS FLOAT), 2) AS line_total_kes,
        
        -- Data validation
        ROUND(CAST([quantity_ordered] AS FLOAT) * CAST([unit_price] AS FLOAT), 2) AS calculated_line_total
        
    FROM [Blue_canopy].[bronze].[purchase_order_lines_raw]
    WHERE [po_number] IS NOT NULL 
        AND [product_id] IS NOT NULL
),

validated AS (
    SELECT 
        *,
        
        -- Validation flag
        CASE 
            WHEN quantity_ordered <= 0 THEN 'Invalid quantity'
            WHEN unit_price_kes <= 0 THEN 'Invalid unit price'
            WHEN line_total_kes <= 0 THEN 'Invalid line total'
            WHEN calculated_line_total != line_total_kes THEN 'Line total mismatch'
            ELSE 'Valid'
        END AS quality_flag,
        
        -- PO metadata
        LEFT(po_number, 2) AS po_prefix,
        TRY_CAST(RIGHT(po_number, 8) AS INT) AS po_sequence_number,
        
        -- Line metadata
        CONCAT(po_number, '_', line_number) AS po_line_key,
        
        -- Cost calculations
        ROUND(line_total_kes / NULLIF(quantity_ordered, 0), 2) AS calculated_unit_price,
        ROUND(line_total_kes * 1.10, 2) AS landed_cost_kes,  -- Assuming 10% landed cost
        ROUND(line_total_kes * 0.16, 2) AS estimated_vat_kes  -- 16% VAT in Kenya
        
    FROM base
),

-- STEP 1: Clean the data and apply ABS()
deduplicated AS (
    SELECT 
        po_line_key,
        po_number,
        line_number,
        product_id,
        ABS(quantity_ordered) AS quantity_ordered,
        ABS(unit_price_kes) AS unit_price_kes,
        ABS(line_total_kes) AS line_total_kes,
        ABS(calculated_unit_price) AS calculated_unit_price,
        ABS(landed_cost_kes) AS landed_cost_kes,
        ABS(estimated_vat_kes) AS estimated_vat_kes,
        po_prefix,
        po_sequence_number,
        quality_flag,
        GETDATE() AS etl_load_date,
        'silver.purchase_order_lines' AS etl_source
    FROM validated
    WHERE po_number NOT LIKE '%DUP'
),

-- STEP 2: Consolidate multiple lines of the same product into one line
aggregated AS (
    SELECT 
        po_number,
        product_id,
        
        -- Summed Metrics
        SUM(quantity_ordered) AS quantity_ordered,
        SUM(line_total_kes) AS line_total_kes,
        SUM(landed_cost_kes) AS landed_cost_kes,
        SUM(estimated_vat_kes) AS estimated_vat_kes,
        
        -- Price Metrics (Taking the MAX price since summing prices is incorrect)
        MAX(unit_price_kes) AS unit_price_kes,
        MAX(calculated_unit_price) AS calculated_unit_price,
        
        -- PO Metadata (Static per PO)
        MAX(po_prefix) AS po_prefix,
        MAX(po_sequence_number) AS po_sequence_number,
        
        -- Quality Flag
        CASE 
            WHEN COUNT(CASE WHEN quality_flag != 'Valid' THEN 1 END) > 0 THEN 'Contains Invalid Lines'
            ELSE 'Valid'
        END AS quality_flag,
        
        -- Audit
        MAX(etl_load_date) AS etl_load_date,
        MAX(etl_source) AS etl_source
    FROM deduplicated
    GROUP BY po_number, product_id
),

-- STEP 3: Generate fresh, sequential line numbers and new po_line_keys
final_transform AS (
    SELECT 
        -- Generate new sequential line number per PO
        ROW_NUMBER() OVER (PARTITION BY po_number ORDER BY product_id) AS line_number,
        
        -- Reconstruct the surrogate key using the new line number
        CONCAT(po_number, '_', ROW_NUMBER() OVER (PARTITION BY po_number ORDER BY product_id)) AS po_line_key,
        
        po_number,
        product_id,
        quantity_ordered,
        line_total_kes,
        landed_cost_kes,
        estimated_vat_kes,
        unit_price_kes,
        calculated_unit_price,
        po_prefix,
        po_sequence_number,
        quality_flag,
        etl_load_date,
        etl_source
    FROM aggregated
)

-- STEP 4: Insert into the silver table
SELECT 
    po_line_key,
    po_number,
    line_number,
    product_id,
    quantity_ordered,
    unit_price_kes,
    line_total_kes,
    calculated_unit_price,
    landed_cost_kes,
    estimated_vat_kes,
    po_prefix,
    po_sequence_number,
    quality_flag,
    etl_load_date,
    etl_source
INTO silver.purchase_order_lines
FROM final_transform;
