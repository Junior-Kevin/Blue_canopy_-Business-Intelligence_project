DROP TABLE IF EXISTS Blue_canopy.gold.dim_competitors;
GO
SELECT ROW_NUMBER() OVER(ORDER BY competitor_id) competitor_key
      , [competitor_id]
      ,[competitor_name]
  INTO Blue_canopy.gold.dim_competitors
  FROM [Blue_canopy].[silver].[competitors]
