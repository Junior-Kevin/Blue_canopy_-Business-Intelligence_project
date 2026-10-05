USE Blue_canopy;
GO
DROP TABLE IF EXISTS silver.products;
GO
WITH main AS (
SELECT  
       product_sk  = CONVERT(INT,ROW_NUMBER() OVER (ORDER BY product_id, valid_from))
	  ,ROW_NUMBER() OVER(PARTITION BY product_id ORDER BY valid_from) flag
	  ,CASE WHEN product_id LIKE '%DUP' THEN LEFT(product_id,9) ELSE product_id END AS product_id
	  ,[product_name]
	  ,[brand]
      ,[category]
      ,[subcategory]
	  ,CASE WHEN supplier_id LIKE '%DUP' THEN LEFT(supplier_id,8) ELSE supplier_id END AS supplier_id
      ,CAST([unit_cost_kes] AS FLOAT) unit_cost_kes
      ,CAST([retail_price_kes] AS FLOAT)  retail_price_kes
      ,CAST([margin_percentage] AS FLOAT) margin_percentage 
	  ,margin_band =  CASE
	                      WHEN CAST([margin_percentage] AS FLOAT) < 20 THEN 'low'
						  WHEN CAST([margin_percentage] AS FLOAT) Between 20 and 40  THEN 'medium' 
						  WHEN CAST([margin_percentage] AS FLOAT) > 40 THEN 'high'
					  END
      ,FORMAT(CAST(CASE 
	             WHEN [valid_from] IS NULL THEN GETDATE()  
				 WHEN valid_from = '2023-13-45' THEN '2023-12-25'
			     ELSE valid_from
			  END AS DATE), 'yyyy-MM-dd') valid_from
	  ,[is_active] 
      ,FORMAT(CAST(CASE 
	             WHEN [introduction_date] IS NULL THEN GETDATE()  
				 WHEN introduction_date = '2023-13-45' THEN '2023-12-25'
			     ELSE introduction_date 
			  END AS DATE), 'yyyy-MM-dd') introduction_date
	  ,FORMAT(CAST(CASE 
	             WHEN [valid_to] IS NULL THEN GETDATE()  
				 WHEN valid_to = '2023-13-45' THEN '2023-12-25'
			     ELSE valid_to 
			  END AS DATE), 'yyyy-MM-dd') valid_to
	  ,FORMAT(CAST(CASE 
	             WHEN [discontinued_date] IS NULL THEN GETDATE()  
				 WHEN discontinued_date = '2023-13-45' THEN '2023-12-25'
			     ELSE discontinued_date
			  END AS DATE), 'yyyy-MM-dd') discontinued_date
	  ,is_current_version = CASE WHEN valid_to IS NULL THEN 'yes' ELSE 'no' END
  FROM [Blue_canopy].[bronze].[products_raw]
  ) SELECT product_sk
     	  ,product_id
	  ,[product_name]
	  ,[brand]
      ,[category]
      ,[subcategory]
	  ,[supplier_id]
	  ,[unit_cost_kes]
      ,[retail_price_kes]
      ,[margin_percentage]
	  ,margin_band
	  ,CASE WHEN flag = 1 THEN CAST('2016-01-01' AS DATE) ELSE introduction_date END AS introduction_date
	  ,CASE WHEN flag = 1 THEN CAST('2016-01-01' AS DATE) ELSE valid_from END AS valid_from
	  ,valid_to
	  ,discontinued_date
	  ,is_active
	  ,is_current_version
	  INTO silver.products
	  FROM main
	  ORDER BY product_sk, product_id,valid_from;
GO
CREATE NONCLUSTERED COLUMNSTORE INDEX idx_product_product_id ON 
silver.products (product_id)
