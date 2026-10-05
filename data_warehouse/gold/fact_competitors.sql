DROP TABLE IF EXISTS Blue_canopy.gold.fact_competitors;
GO
SELECT [comp_qtr_key]
      ,competitor_key
      ,[store_name]
      ,[county_key]
      ,[quarter]
      ,[revenue_kes]
      ,[market_share_pct]
INTO Blue_canopy.gold.fact_competitors
FROM [Blue_canopy].[silver].[competitor_quarterly] sc
LEFT JOIN [Blue_canopy].[gold].[dim_competitors] gc
ON sc.competitor_id = gc.competitor_id
