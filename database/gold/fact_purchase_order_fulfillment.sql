-- ==========================================================
-- GOLD LAYER: FACT PURCHASE ORDER FULFILLMENT
-- Grain: One row per Product per Purchase Order
-- ==========================================================

DROP TABLE IF EXISTS gold.fact_purchase_order_fulfillment;

WITH ReceiptAggregated AS (
    -- Aggregate the batch receipts into a single row per PO + Product
    SELECT 
        po_number,
        product_id,
        SUM(quantity_received) AS total_quantity_received,
        SUM(CASE WHEN has_quality_issue = 0 THEN quantity_received ELSE 0 END) AS total_good_quantity_received,
        SUM(CASE WHEN has_quality_issue = 1 THEN quantity_received ELSE 0 END) AS total_issue_quantity_received,
        
        MIN(receipt_date) AS first_receipt_date,
        MAX(receipt_date) AS last_receipt_date,
        COUNT(DISTINCT receipt_id) AS number_of_batches
    FROM silver.goods_receipts
    GROUP BY po_number, product_id
)

SELECT 
    -- Keys (Foreign Keys to Dimensions)
	ROW_NUMBER() OVER(ORDER BY po.order_date) purchase_orders_sk,  
    pol.po_number,
    dpb.product_key,
    dsb.supplier_key,
    
    -- Dates
    po.order_date,
    ra.first_receipt_date,
    ra.last_receipt_date,
    
    -- Line-level attributes
    pol.line_number,
    pol.quantity_ordered,
    pol.unit_price_kes,
    pol.line_total_kes,
    pol.landed_cost_kes,
    pol.estimated_vat_kes,
    
    -- Received measures
    ISNULL(ra.total_quantity_received, 0)        AS total_quantity_received,
    ISNULL(ra.total_good_quantity_received, 0)   AS total_good_quantity_received,
    ISNULL(ra.total_issue_quantity_received, 0)  AS total_issue_quantity_received,
    ISNULL(ra.number_of_batches, 0)              AS number_of_batches,
    
    -- Calculated measures
    CASE 
        WHEN pol.quantity_ordered - ISNULL(ra.total_quantity_received, 0) < 0 THEN 0 
        ELSE pol.quantity_ordered - ISNULL(ra.total_quantity_received, 0) 
    END AS quantity_outstanding,
    
    CASE 
        WHEN ISNULL(ra.total_quantity_received, 0) > pol.quantity_ordered 
            THEN ISNULL(ra.total_quantity_received, 0) - pol.quantity_ordered
        ELSE 0 
    END AS quantity_over_received,
    
    -- Fulfillment status
    CASE 
        WHEN ISNULL(ra.total_quantity_received, 0) = 0 THEN 'Not Received'
        WHEN ISNULL(ra.total_quantity_received, 0) > pol.quantity_ordered THEN 'Over Received'
        WHEN ISNULL(ra.total_quantity_received, 0) = pol.quantity_ordered THEN 'Fully Received'
        ELSE 'Partially Received'
    END AS fulfillment_status,
    
    -- Audit
    GETDATE() AS etl_load_date,
    'gold.fact_purchase_order_fulfillment' AS etl_source

INTO gold.fact_purchase_order_fulfillment
FROM silver.purchase_order_lines pol
LEFT JOIN silver.purchase_orders po 
    ON pol.po_number = po.po_number
LEFT JOIN ReceiptAggregated ra 
    ON pol.po_number = ra.po_number 
    AND pol.product_id = ra.product_id
LEFT JOIN[gold].[dim_product_bridge] dpb
ON pol.product_id = dpb.product_id
LEFT JOIN [gold].[dim_supplier_bridge] dsb
ON po.supplier_id = dsb.supplier_id;
