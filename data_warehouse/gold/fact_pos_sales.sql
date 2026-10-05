DROP TABLE IF EXISTS gold.fact_sales;
GO

;
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
final AS (
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
)

SELECT * INTO gold.fact_sales FROM (
    SELECT 
        [transaction_id]
        , [store_id]
        , [customer_id]
        , [cashier_id]
        , [product_id]
        , supplier_id
        , [delivery_address] = NULL
        , payment_method
        , [order_status] = 'delivered'
        , [delivery_fee] = 0
        , [transaction_date]
        , [transaction_time]
        , [line_number]
        , [quantity]
        , [unit_price_kes]
        , [discount_rate]
        , [discount_amount_kes]
        , [unit_price_after_discount_kes] = [effective_unit_price_kes]
        , [line_total]
        , [unit_cost_kes] 
    FROM final
    WHERE S_NO = 1
    
    UNION ALL
    
    SELECT 
        [transaction_id] = [order_id]
        , store_id
        , [customer_id]
        , [cashier_id] = NULL
        , [product_id]
        , [supplier_id]
        , [delivery_address]
        , [payment_method]
        , [order_status]
        , [delivery_fee]
        , [transaction_date] = order_date
        , [transaction_time] = [order_time]
        , [line_number]
        , [quantity]
        , [unit_price_kes]
        , [discount_rate]
        , [discount_amount_kes]
        , [unit_price_after_discount_kes]
        , line_total = [line_total_kes]
        , [unit_cost_kes] 
    FROM (
        SELECT ROW_NUMBER() OVER(PARTITION BY order_line_key ORDER BY order_date, ol.order_id, line_number) AS order_line_key_new
            , [order_line_key]
            , ol.[order_id]
            , [line_number]
            , ol.[product_id]
            , [supplier_id]
            , eo.[customer_id]
            , store_id = cst.primary_store_id
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
            , [line_total_kes]
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
    ) t
    WHERE order_line_key_new = 1
) combined;

