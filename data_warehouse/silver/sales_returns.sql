
DROP TABLE IF EXISTS silver.sales_returns 
GO
SELECT [return_id]
      ,[original_transaction_id]
	  ,dpb.product_key
      ,spr.[product_id]
      ,[return_date]
      ,[quantity_returned]
      ,[refund_amount]
      ,[return_reason]
INTO silver.sales_returns
FROM [Blue_canopy].[silver].[pos_returns] spr
LEFT JOIN [gold].[dim_product_bridge]  dpb
ON spr.product_id = dpb.product_id
--WHERE NOT ([original_transaction_id] = 'TXN-2313019' AND [return_date] = '2024-09-30')

UNION ALL

SELECT [return_id]
      ,[original_transaction_id]
	  ,pb.product_key
      ,ser.[product_id]
      ,[return_date]
      ,[quantity_returned]
      ,[refund_amount]
      ,[return_reason]
FROM [Blue_canopy].[silver].[ecomerce_returns] ser
LEFT JOIN [gold].[dim_product_bridge]  pb
ON ser.product_id = pb.product_id

ORDER BY 1,2;
