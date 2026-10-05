DROP TABLE IF EXISTS silver.gis_counties;
SELECT 
        ROW_NUMBER() OVER(ORDER BY county) county_key
       ,[county]
      ,CAST ([population] AS INT)  population
      ,CAST([avg_income_kes] AS INT) avg_income_kes
      ,CAST([latitude] AS FLOAT) latitude 
      ,CAST([longitude] AS FLOAT) longitude
 INTO silver.gis_counties
 FROM [Blue_canopy].[bronze].[gis_counties_raw];
