DROP TABLE IF EXISTS Blue_canopy.gold.dim_competitors_stores;
GO
SELECT ROW_NUMBER() OVER(ORDER BY SR.[competitor_id]) competitor_store_key
      ,SR.[competitor_id]
	  ,[competitor_store_id]
      ,SUBSTRING([location],
	  CHARINDEX('-',location,1)+1,30) location
      ,[county]
      ,[size_category]
	  INTO Blue_canopy.gold.dim_competitors_stores
  FROM [Blue_canopy].[silver].[competitors_stores] SR
  LEFT JOIN [Blue_canopy].[gold].[dim_competitors] CR
  ON SR.competitor_id  = CR.competitor_id

