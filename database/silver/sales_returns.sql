
DROP TABLE IF EXISTS silver.sales_returns 
GO
SELECT [return_id]
      ,[original_transaction_id]
      ,[product_id]
      ,[return_date]
      ,[quantity_returned]
      ,[refund_amount]
      ,[return_reason]
INTO silver.sales_returns
FROM [Blue_canopy].[silver].[pos_returns]

UNION ALL

SELECT [return_id]
      ,[original_transaction_id]
      ,[product_id]
      ,[return_date]
      ,[quantity_returned]
      ,[refund_amount]
      ,[return_reason]
FROM [Blue_canopy].[silver].[ecomerce_returns]

ORDER BY 1,2;
