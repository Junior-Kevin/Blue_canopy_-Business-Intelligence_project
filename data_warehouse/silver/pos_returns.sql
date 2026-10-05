DROP TABLE IF EXISTS silver.pos_returns;
GO
SELECT [return_id]
      ,REPLACE([original_transaction_id],' ','') original_transaction_id
	  ,CAST(CASE WHEN return_date = '2023-13-45' THEN '2023-12-25'
	        ELSE return_date END AS DATE) return_date
      ,CASE WHEN product_id LIKE '%DUP' THEN LEFT(product_id,9) ELSE product_id END AS product_id
      ,CAST([quantity_returned] AS INT) quantity_returned 
      ,CAST([refund_amount] AS FLOAT) refund_amount
      ,[return_reason]
  INTO silver.pos_returns
  FROM [Blue_canopy].[bronze].[returns_raw]
  WHERE original_transaction_id LIKE 'TXN%'
  AND return_id NOT LIKE '%DUP'
