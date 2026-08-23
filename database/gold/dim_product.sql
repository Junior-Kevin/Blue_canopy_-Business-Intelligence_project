USE Blue_canopy;
GO
DROP TABLE IF EXISTS gold.dim_product;
GO
WITH main AS (
SELECT  
       product_sk  = CONVERT(INT,ROW_NUMBER() OVER (ORDER BY product_id, valid_from))
	  ,ROW_NUMBER() OVER(PARTITION BY product_id ORDER BY valid_from) flag
	  ,product_id
	  ,LEAD(product_id) OVER(PARTITION BY product_id ORDER BY product_id ) product_lag
	  ,LAG(product_id) OVER(PARTITION BY product_id ORDER BY product_id ) product_lag1
	  ,[product_name]
	  ,[brand]
      ,[category]
      ,[subcategory]
	  ,[supplier_id]
	  ,[unit_cost_kes]
      ,[retail_price_kes]
      ,[margin_percentage]
	  ,margin_band =  CASE
	                      WHEN margin_percentage < 20 THEN 'low'
						  WHEN margin_percentage Between 20 and 40  THEN 'medium' 
						  WHEN margin_percentage > 40 THEN 'high'
					  END
      ,[introduction_date]
	  ,[is_active] 
      ,FORMAT(
	        COALESCE(CAST(DATEADD(day,1,LAG(valid_to) 
            OVER(PARTITION BY product_id ORDER BY valid_from,valid_to)) AS DATE),valid_from),
			'yyyy-MM-dd') valid_from
      ,FORMAT(CASE WHEN [valid_to] IS NULL THEN GETDATE() 
            ELSE [valid_to] END, 'yyyy-MM-dd') valid_to
	  ,FORMAT(CASE WHEN [discontinued_date] IS NULL THEN GETDATE() 
            ELSE [discontinued_date] END, 'yyyy-MM-dd') discontinued_date
	  ,is_current_version = CASE WHEN valid_to IS NULL THEN 'yes' ELSE 'no' END
  FROM [Blue_canopy].[silver].[products]
  ) SELECT product_sk
            --,flag
     	  ,product_id
		 --,product_lag
		 --,product_lag1
	  ,[product_name]
	  ,[brand]
      ,[category]
      ,[subcategory]
	  ,CASE WHEN [supplier_id] IS NULL AND flag = 1 THEN 'SUP-0018'
	        WHEN [supplier_id] IS NULL AND flag = 2 THEN 'SUP-0060'
			WHEN [supplier_id] IS NULL AND flag = 3 THEN 'SUP-0145'
			WHEN [supplier_id] IS NULL AND flag = 4 THEN 'SUP-0178'
		ELSE supplier_id END AS supplier_id
	  ,[unit_cost_kes]
      ,[retail_price_kes]
      ,[margin_percentage]
	  ,margin_band
	  ,CASE WHEN flag = 1 THEN CAST('2016-01-01' AS DATE) ELSE introduction_date END AS introduction_date
	  ,CASE WHEN flag = 1 THEN CAST('2016-01-01' AS DATE) ELSE valid_from END AS valid_from
	  ,CASE WHEN flag = 1 AND product_lag IS NULL THEN CAST(GETDATE() AS DATE)
	        WHEN product_lag IS NULL THEN CAST(GETDATE() AS DATE)
	    ELSE valid_to END AS valid_to
	  ,discontinued_date
	  ,is_active
	  ,is_current_version
	  INTO gold.dim_product
	  FROM main
	  ORDER BY product_sk, product_id,valid_from;
GO
CREATE NONCLUSTERED COLUMNSTORE INDEX idx_product_product_id ON 
gold.dim_product (product_id)
