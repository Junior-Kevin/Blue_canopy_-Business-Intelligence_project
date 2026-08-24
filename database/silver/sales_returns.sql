
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
WHERE NOT ([original_transaction_id] = 'TXN-2313019' AND [return_date] = '2024-09-30')

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
