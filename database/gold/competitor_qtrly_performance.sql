DROP TABLE IF EXISTS Blue_canopy.gold.competitor_qtrly_performance;
GO
SELECT  [comp_qtr_key]
      ,[competitor_key]
      ,competitor_store_key
	  ,e.county_key
      ,[quarter]
      ,[revenue_kes]
      ,[market_share_pct]
	  INTO Blue_canopy.gold.competitor_qtrly_performance
  FROM [Blue_canopy].[silver].[competitor_quarterly] b
  LEFT JOIN [Blue_canopy].[gold].[dim_competitors] c
  ON b.competitor_id = c.competitor_id
  LEFT JOIN [Blue_canopy].[gold].[dim_competitors_stores] d
  ON b.store_name = d.[competitor_store_id]
  LEFT JOIN [silver].[gis_counties]  e
  ON d.county = e.county
  ORDER BY [comp_qtr_key]
