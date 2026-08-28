DROP TABLE IF EXISTS Blue_canopy.gold.fact_sales;
GO

WITH line_items AS (	
    SELECT [pos_line_key]
        , pli.[transaction_id]
        , [store_id]
        , [customer_id]
        , [cashier_id]
        , pli.[product_id]
        , payment_method
        , [transaction_date]
        , [transaction_time]
        , [line_number]
        , [quantity]
        , [unit_price_kes]
        , [discount_rate]
        , [effective_unit_price_kes]
        , [discount_amount_kes]
        , pli.[line_total]
    FROM [Blue_canopy].[silver].[pos_line_items] pli
    LEFT JOIN [Blue_canopy].[silver].[pos_transactions] pt
        ON pli.transaction_id = pt.transaction_id
),
products AS (
    SELECT product_id
        , supplier_id
        , valid_from
        , valid_to
        , [unit_cost_kes]
    FROM [Blue_canopy].[gold].[dim_product]
),
pos_final AS (
    SELECT ROW_NUMBER() OVER(PARTITION BY pos_line_key ORDER BY transaction_date) AS S_NO
        , [pos_line_key]
        , [transaction_id]
        , [store_id]
        , [customer_id]
        , [cashier_id]
        , li.[product_id]
        , supplier_id
        , payment_method
        , [transaction_date]
        , transaction_time
        , [line_number]
        , [quantity]
        , [unit_price_kes]
        , [discount_rate]
        , [effective_unit_price_kes]
        , [discount_amount_kes]
        , pr.[unit_cost_kes]
        , [line_total]
    FROM line_items li
    LEFT JOIN products pr
        ON li.product_id = pr.product_id 
        AND (li.transaction_date BETWEEN pr.valid_from AND pr.valid_to)
),
pos_combined AS (
    SELECT 
        [transaction_id]
        , sb.store_key
        , dc.[customer_key]
        , eb.employee_key AS cashier_key
        , pb.[product_key]
        , sbb.supplier_key
        , 'on_counter' AS delivery_address
        , payment_method
        , 'delivered' AS order_status
        , 0 AS delivery_fee
        , [transaction_date]
        , [transaction_time]
        , [line_number]
        , [quantity]
        , [unit_price_kes]
        , [discount_rate]
        , [discount_amount_kes]
        , [effective_unit_price_kes] AS unit_price_after_discount_kes
        , [line_total]
        , [unit_cost_kes]
        , NULL AS return_reason
        , NULL AS quantity_returned
        , NULL AS refund_amount
    FROM pos_final ss
    LEFT JOIN [Blue_canopy].gold.dim_store_bridge sb
        ON ss.store_id = sb.store_id
    LEFT JOIN [Blue_canopy].[gold].[dim_employee_bridge] eb
        ON ss.cashier_id = eb.employee_id
    LEFT JOIN [gold].[dim_customers] dc
        ON ss.customer_id = dc.customer_id
    LEFT JOIN [gold].[dim_product_bridge] pb
        ON ss.product_id = pb.product_id
    LEFT JOIN [gold].[dim_supplier_bridge] sbb
        ON ss.supplier_id = sbb.supplier_id
    WHERE S_NO = 1
),
ecom_final AS (
    SELECT ROW_NUMBER() OVER(PARTITION BY order_line_key ORDER BY order_date, ol.order_id, line_number) AS order_line_key_new
        , [order_line_key]
        , ol.[order_id]
        , [line_number]
        , pb.[product_key]
        , sbb.[supplier_key]
        , dc.[customer_key]
        , sb.store_key
        , [order_date]
        , [order_time]
        , [delivery_address]
        , [delivery_fee]
        , [payment_method]
        , [order_status]
        , [quantity]
        , [unit_price_kes]
        , [discount_rate]
        , [discount_amount_kes]
        , [unit_price_after_discount_kes]
        , [line_total_kes] AS line_total
        , [unit_cost_kes]
    FROM [Blue_canopy].[silver].[ecommerce_order_lines] ol
    LEFT JOIN [Blue_canopy].[silver].[ecommerce_orders] eo
        ON ol.order_id = eo.order_id
    LEFT JOIN [Blue_canopy].[gold].[dim_product] P
        ON ol.product_id = P.product_id AND order_date BETWEEN valid_from AND valid_to
    LEFT JOIN [Blue_canopy].[gold].[dim_customers] dc
        ON eo.customer_id = dc.customer_id
    LEFT JOIN [Blue_canopy].[silver].[cust_county] cst
        ON eo.customer_id = cst.customer_id
    LEFT JOIN [Blue_canopy].gold.dim_store_bridge sb
        ON cst.primary_store_id = sb.store_id
    LEFT JOIN Blue_canopy.gold.dim_product_bridge pb
        ON ol.product_id = pb.product_id
    LEFT JOIN [gold].[dim_supplier_bridge] sbb
        ON P.supplier_id = sbb.supplier_id
),
ecom_combined AS (
    SELECT 
        [order_id] AS transaction_id
        , store_key
        , [customer_key]
        , 0 AS cashier_key
        , [product_key]
        , [supplier_key]
        , [delivery_address]
        , [payment_method]
        , [order_status]
        , [delivery_fee]
        , [order_date] AS transaction_date
        , [order_time] AS transaction_time
        , [line_number]
        , [quantity]
        , [unit_price_kes]
        , [discount_rate]
        , [discount_amount_kes]
        , [unit_price_after_discount_kes]
        , [line_total]
        , [unit_cost_kes]
        , NULL AS return_reason
        , NULL AS quantity_returned
        , NULL AS refund_amount
    FROM ecom_final
    WHERE order_line_key_new = 1
),
combined_sales AS (
    SELECT * FROM pos_combined
    UNION ALL
    SELECT * FROM ecom_combined
),
sales_with_returns AS (
    SELECT 
        ROW_NUMBER() OVER(ORDER BY transaction_date) AS sales_sk
        ,[transaction_id]
        ,[store_key]
        ,[customer_key]
        ,[cashier_key]
        ,fs.[product_key]
        ,[supplier_key]
        ,[delivery_address]
        ,[payment_method]
        ,[order_status]
        ,[delivery_fee]
        ,[transaction_date]
        ,[transaction_time]
        ,[line_number]
        ,[quantity]
        ,[unit_price_kes]
        ,[discount_rate]
        ,[discount_amount_kes]
        ,[unit_price_after_discount_kes]
        ,[line_total]
        ,[unit_cost_kes]
        ,CASE 
            WHEN sr.[return_reason] = 'Wrong Item' THEN DATEADD(day,3,transaction_date)
            WHEN sr.[return_reason] = 'Defective' THEN DATEADD(day,5,transaction_date)
            WHEN sr.[return_reason] = 'Size/Fit Issue' THEN DATEADD(day,7,transaction_date)
            WHEN sr.[return_reason] = 'Damaged' THEN DATEADD(day,9,transaction_date)
            WHEN sr.[return_reason] = 'Changed Mind' THEN DATEADD(day,1,transaction_date)
            WHEN sr.[return_reason] = 'Not as Described' THEN DATEADD(day,2,transaction_date)
            ELSE NULL 
        END AS return_date
        ,sr.[quantity_returned]
        ,sr.[refund_amount]
        ,sr.[return_reason]
        ,CASE 
            WHEN sr.quantity_returned IS NULL THEN fs.quantity 
            ELSE fs.quantity - sr.quantity_returned   
        END AS net_quantity              
        ,CASE 
            WHEN sr.[refund_amount] IS NULL THEN fs.line_total
            ELSE fs.line_total - sr.[refund_amount] 
        END AS net_sales
    FROM combined_sales fs
    LEFT JOIN [Blue_canopy].[silver].[sales_returns] sr
        ON fs.transaction_id = sr.original_transaction_id
        AND fs.product_key = sr.product_key
)
SELECT 
    [sales_sk]
    ,[transaction_id]
    ,[store_key]
    ,[customer_key]
    ,[cashier_key]
    ,[product_key]
    ,[supplier_key]
    ,sj.sales_junk_key
    ,[delivery_fee]
    ,[transaction_date]
    ,[transaction_time]
    ,[line_number]
    ,[quantity]
    ,[unit_price_kes]
    ,[discount_rate]
    ,[discount_amount_kes]
    ,[unit_price_after_discount_kes]
    ,[line_total]
    ,[unit_cost_kes]
    ,[return_date]
    ,[quantity_returned]
    ,[refund_amount]
    ,[net_quantity]
    ,[net_sales]
INTO Blue_canopy.gold.fact_sales
FROM sales_with_returns fs
LEFT JOIN Blue_canopy.gold.dim_sales_junk sj
    ON fs.[payment_method] = sj.[payment_method]
    AND fs.[order_status] = sj.[order_status] 
    AND (fs.[return_reason] = sj.[return_reason] 
         OR (fs.[return_reason] IS NULL AND sj.[return_reason] IS NULL));
