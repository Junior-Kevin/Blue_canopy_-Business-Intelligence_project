
DROP TABLE IF EXISTS Blue_canopy.gold.competitor_qtrly_performance;
GO
SELECT  [comp_qtr_key]
	  ,gdc.competitor_key
      ,cq.[competitor_store_id]
	  ,gl.location_id
      ,gbc.county_key
      ,cs.[size_category]
      ,[quarter]
      ,[revenue_kes]
      ,[market_share_pct]
  INTO  Blue_canopy.gold.competitor_qtrly_performance
  FROM [Blue_canopy].[silver].[competitor_quarterly] cq
  LEFT JOIN [Blue_canopy].[silver].[competitor_stores] cs
  ON cq.competitor_store_id = cs.competitor_store_id
  LEFT JOIN [Blue_canopy].[gold].[dim_competitors] gdc
  ON cq.competitor_id = gdc.competitor_id
  LEFT JOIN gold.bridge_counties gbc
  ON cs.county = gbc.county
  LEFT JOIN [silver].[gis_locations]  gl
  ON cs.location = gl.town
