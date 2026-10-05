
DROP TABLE IF EXISTS silver.stores;
GO
SELECT ROW_NUMBER() OVER(ORDER BY store_id,valid_from) store_key
       ,[store_id]
      ,FORMAT(CAST(CASE 
	             WHEN [valid_from] IS NULL THEN GETDATE()  
				 WHEN valid_from = '2023-13-45' THEN '2023-12-25'
			     ELSE valid_from
			  END AS DATE), 'yyyy-MM-dd') valid_from
     ,FORMAT(CAST(CASE 
	             WHEN [valid_to] IS NULL THEN GETDATE()  
				 WHEN valid_to = '2023-13-45' THEN '2023-12-25'
			     ELSE valid_to 
			  END AS DATE), 'yyyy-MM-dd') valid_to
      ,REPLACE([store_name],'Blue Canopy','bc_')  store_name
      ,[county]
	  ,SUBSTRING(REPLACE([store_name],'Blue Canopy','bc_'),4,20) town
      ,COALESCE([format],LAG(format) OVER(order by store_id)) [format]
      ,CAST([size_sqm] AS INT) size_sqm
      ,FORMAT(CAST(CASE  
				 WHEN opening_date = '2023-13-45' THEN '2023-12-25'
			     ELSE opening_date
			  END AS DATE), 'yyyy-MM-dd') opening_date
      ,FORMAT(CAST(CASE 
	             WHEN [closing_date] IS NULL THEN GETDATE()  
				 WHEN closing_date = '2023-13-45' THEN '2023-12-25'
			     ELSE closing_date
			  END AS DATE), 'yyyy-MM-dd') closing_date
      ,CASE WHEN [is_active] = 'TRUE' THEN 'yes' ELSE 'no'END AS is_active
INTO silver.stores
  FROM [Blue_canopy].[bronze].[stores_raw]
  WHERE store_id NOT LIKE '%DUP'
