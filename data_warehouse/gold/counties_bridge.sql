 DROP TABLE IF EXISTS gold.dim_counties;
GO
SELECT  [county_key]
      ,[county]
	  INTO gold.bridge_counties
FROM [Blue_canopy].[silver].[gis_counties]
