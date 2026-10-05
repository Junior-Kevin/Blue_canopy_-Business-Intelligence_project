DROP TABLE IF EXISTS silver.purchase_orders;

WITH base AS (
    SELECT 
        [po_number],
        
        -- Fix dates
        CAST(
            CASE 
                WHEN order_date = '2023-13-45' THEN '2022-10-15'
                ELSE order_date
            END AS DATE
        ) AS order_date,
        
        -- Clean supplier ID
        CASE 
            WHEN supplier_id LIKE '%-DUP%' THEN LEFT(supplier_id, CHARINDEX('-DUP', supplier_id) - 1)
            ELSE supplier_id
        END AS supplier_id_clean,
        
        -- Fix expected delivery date
        CAST(
            CASE 
                WHEN expected_delivery_date = '2023-13-45' THEN '2022-10-15'
                ELSE expected_delivery_date
            END AS DATE
        ) AS expected_delivery_date,
        
        [status],
        ROUND(CAST([total_amount] AS FLOAT), 2) AS total_amount_kes
        
    FROM [Blue_canopy].[bronze].[purchase_orders_raw]
    WHERE [po_number] IS NOT NULL
),

calculated AS (
    SELECT 
        *,
        
        -- PO metadata
        LEFT(po_number, 2) AS po_prefix,
        TRY_CAST(RIGHT(po_number, 8) AS INT) AS po_sequence_number,
        
        -- Time-based calculations
        YEAR(order_date) AS order_year,
        MONTH(order_date) AS order_month,
        DATEPART(QUARTER, order_date) AS order_quarter,
        FORMAT(order_date, 'yyyy-MM') AS order_year_month,
        
        -- Delivery metrics
        DATEDIFF(DAY, order_date, expected_delivery_date) AS expected_lead_time_days,
        
        -- Status categorization
        CASE 
            WHEN status = 'Closed' THEN 'Completed'
            WHEN status = 'Open' THEN 'In Progress'
            WHEN status = 'Cancelled' THEN 'Cancelled'
            ELSE 'Unknown'
        END AS status_category,
        
        -- Order aging (days since order)
        DATEDIFF(DAY, order_date, GETDATE()) AS days_since_order,
        
        -- Data quality
        CASE 
            WHEN total_amount_kes <= 0 THEN 'Invalid total amount'
            WHEN order_date > expected_delivery_date THEN 'Order date after expected delivery'
            WHEN order_date IS NULL THEN 'Missing order date'
            WHEN expected_delivery_date IS NULL THEN 'Missing expected delivery date'
            WHEN supplier_id_clean IS NULL OR supplier_id_clean = '' THEN 'Missing supplier'
            WHEN status NOT IN ('Closed', 'Open', 'Cancelled') THEN 'Invalid status'
            ELSE 'Valid'
        END AS quality_flag
        
    FROM base
)

SELECT 
    -- Surrogate key
    po_number,
    
    -- Primary key for header
    po_number AS purchase_order_key,
    
    -- Dimensions
    supplier_id_clean AS supplier_id,
    status,
    status_category,
    
    -- Dates
    order_date,
    expected_delivery_date,
    
    -- Financial
    total_amount_kes,
    
    -- Time attributes
    order_year,
    order_month,
    order_quarter,
    order_year_month,
    
    -- Metrics
    expected_lead_time_days,
    days_since_order,
    
    -- PO metadata
    po_prefix,
    po_sequence_number,
    
    -- Priority flags
    CASE 
        WHEN status = 'Open' AND DATEDIFF(DAY, order_date, GETDATE()) > 30 THEN 'OVERDUE - Review'
        WHEN status = 'Open' AND DATEDIFF(DAY, order_date, GETDATE()) > 14 THEN 'Pending - Follow up'
        WHEN status = 'Cancelled' THEN 'Cancelled - Investigate'
        WHEN status = 'Closed' THEN 'Complete'
        ELSE 'Normal'
    END AS action_priority,
    
    -- Quality
    quality_flag,
    
    -- Audit
    GETDATE() AS etl_load_date,
    'silver.purchase_orders' AS etl_source
    
INTO silver.purchase_orders
FROM calculated c
WHERE order_date IS NOT NULL AND c.po_number NOT LIKE '%DUP'
ORDER BY order_date DESC, c.po_number
