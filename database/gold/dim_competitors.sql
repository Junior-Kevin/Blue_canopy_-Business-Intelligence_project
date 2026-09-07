DROP TABLE IF EXISTS Blue_canopy.gold.dim_competitors;
GO
SELECT ROW_NUMBER() OVER(ORDER BY SR.[competitor_id]) competitor_key
      ,[competitor_store_id]
      ,SR.[competitor_id]
	  ,competitor_name
      ,[location]
      ,[county]
      ,[size_category]
	  INTO Blue_canopy.gold.dim_competitors
FROM [Blue_canopy].[bronze].[competitor_stores_raw] SR
LEFT JOIN [Blue_canopy].[bronze].[competitors_raw] CR
ON SR.competitor_id  = CR.competitor_id
