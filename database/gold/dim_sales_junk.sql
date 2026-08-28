DROP TABLE IF EXISTS Blue_canopy.gold.dim_sales_junk;
GO
SELECT   ROW_NUMBER() OVER(ORDER BY [payment_method],[order_status]) sales_junk_key  
      ,[payment_method]
      ,[order_status] 
	  ,[return_reason] 
	  INTO Blue_canopy.gold.dim_sales_junk
	  FROM (
SELECT ROW_NUMBER() OVER(PARTITION BY payment_method,order_status,[return_reason]
     ORDER BY payment_method,order_status,[return_reason] ) flag
      ,[payment_method]
      ,[order_status]
	  ,[return_reason]
  FROM [Blue_canopy].[gold].[fact_sales]
  )t WHERE flag = 1

