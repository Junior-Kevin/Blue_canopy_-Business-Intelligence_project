USE Blue_canopy;
DROP TABLE IF EXISTS silver.competitor_stores;
GO
SELECT  [competitor_store_id]
      ,[competitor_id]
      ,[location]
      ,[county]
      ,[size_category]
	  INTO silver.competitor_stores
  FROM [Blue_canopy].[bronze].[competitor_stores_raw]
 
