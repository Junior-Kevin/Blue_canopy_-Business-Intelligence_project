
USE Blue_canopy;
GO
DROP TABLE IF EXISTS gold.ecommerce_fact_sales;
GO
SELECT ROW_NUMBER() OVER(ORDER BY order_date,ol.order_id,line_number) AS order_line_key
      ,ol.[order_id]
      ,[line_number]
      ,ol.[product_id]
	  ,[supplier_id]
	  ,eo.[customer_id]
	  ,store_id = primary_store_id
	  ,[order_date]
      ,[order_time]
      ,[delivery_address]
      ,[delivery_fee]
      ,[payment_method]
      ,[order_status]
      ,[quantity]
	  ,[unit_cost_kes]
      ,[unit_price_kes]
      ,[discount_rate]
      ,[unit_price_after_discount_kes]
      ,[discount_amount_kes]
      ,[line_total_kes]
      ,[discount_tier]
INTO gold.ecommerce_fact_sales
FROM [Blue_canopy].[silver].[ecommerce_order_lines] ol
LEFT JOIN [Blue_canopy].[silver].[ecommerce_orders] eo
ON ol.order_id = eo.order_id
LEFT JOIN [Blue_canopy].[gold].[dim_product] P
ON ol.product_id = P.product_id AND order_date BETWEEN valid_from AND valid_to
LEFT JOIN [Blue_canopy].[gold].[dim_customers] dc
ON eo.customer_id = dc.customer_id
ORDER BY order_date,order_id,line_number
;
CREATE NONCLUSTERED INDEX idx_order_id_ecommerce_orders
ON gold.ecommerce_fact_sales (order_id);
GO
CREATE NONCLUSTERED INDEX idx_product_id_ecommerce_orders
ON gold.ecommerce_fact_sales (product_id);
GO
CREATE NONCLUSTERED INDEX idx_store_id_ecommerce_orders
ON gold.ecommerce_fact_sales (store_id);
GO
CREATE NONCLUSTERED INDEX idx_customer_id_ecommerce_orders
ON gold.ecommerce_fact_sales (customer_id);
