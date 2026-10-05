DROP TABLE IF EXISTS silver.gis_locations;
GO
SELECT [location_id]
      ,[county]
      ,[location_name]
      ,[location_type]
      ,CAST([latitude] AS float) latitude
      ,CAST([longitude] AS FLOAT)  longitude
      ,CAST([accessibility_score] AS FLOAT)  accessibility_score
INTO silver.gis_locations
FROM [Blue_canopy].[bronze].[gis_locations_raw]
