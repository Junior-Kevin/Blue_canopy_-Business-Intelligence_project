
DROP TABLE IF EXISTS silver.competitors;
SELECT  [competitor_id]
      ,[competitor_name]
INTO silver.competitors
FROM [Blue_canopy].[bronze].[competitors_raw]
