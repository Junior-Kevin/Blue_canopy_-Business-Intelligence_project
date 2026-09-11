
USE Blue_canopy;
GO
DROP TABLE IF EXISTS gold.dim_geo_economic;

WITH main AS (
SELECT ROW_NUMBER() OVER(PARTITION BY county ORDER BY date) flag
      ,[county]
	  ,LEAD(county) OVER(PARTITION BY county ORDER BY date) leads
      ,[date]
      ,[month_start_date]
      ,[gdp_growth_pct]
      ,[inflation_pct]
      ,[unemployment_pct]
      ,[consumer_confidence]
      ,[retail_sales_index]
      ,[fuel_price_kes]
      ,[usd_kes_rate]
      ,[real_retail_sales_index]
      ,[economic_health_score]
  FROM [Blue_canopy].[silver].[economic]
  ) , recent_data AS (
  SELECT * FROM main WHERE leads IS NULL)
  ,historical_data AS (
  SELECT  [county_key]
      ,m.[county]
      ,[date]
      ,[month_start_date]
      ,[gdp_growth_pct]
      ,[inflation_pct]
      ,[unemployment_pct]
      ,[consumer_confidence]
      ,[retail_sales_index]
      ,[fuel_price_kes]
      ,[usd_kes_rate]
      ,[real_retail_sales_index]
      ,[economic_health_score]
      ,[population] = NULL
      ,[avg_income_kes] = NULL
	  FROM main m
	  LEFT JOIN [Blue_canopy].[silver].[gis_counties] gc
	  ON m.county = gc.county
	  WHERE leads IS NOT NULL),
recent_f  AS (
  SELECT 
       [county_key]
      ,rd.[county]
      ,[date]
      ,[month_start_date]
      ,[gdp_growth_pct]
      ,[inflation_pct]
      ,[unemployment_pct]
      ,[consumer_confidence]
      ,[retail_sales_index]
      ,[fuel_price_kes]
      ,[usd_kes_rate]
      ,[real_retail_sales_index]
      ,[economic_health_score]
      ,[population]
      ,[avg_income_kes]
        FROM recent_data rd
  INNER JOIN [Blue_canopy].[silver].[gis_counties] gc
  ON rd.county = gc.county)
  (SELECT *
  INTO gold.dim_geo_economic
  FROM historical_data
  UNION ALL
  SELECT * FROM recent_f)
  ORDER BY 2,3
