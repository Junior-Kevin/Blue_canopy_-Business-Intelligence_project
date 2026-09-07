DROP TABLE IF EXISTS Blue_canopy.gold.fact_campaign;
GO
SELECT campaign_key
      ,[start_date]
      ,[end_date]
	  ,[campaign_duration_days]
      ,[budget_kes]
      ,variance
      ,[actual_spend_kes]
      ,[discount_rate]
  INTO  Blue_canopy.gold.fact_campaign
  FROM [Blue_canopy].[silver].[campaigns] sc
  LEFT JOIN Blue_canopy.gold.dim_campaign gc
  ON   sc.[campaign_id]= gc.[campaign_id]
  AND  sc.[campaign_name]=gc.[campaign_name]
  AND   sc.[campaign_type]=gc.[campaign_type]
  AND  sc.[channel]=  gc. [channel]
  ORDER BY 1
