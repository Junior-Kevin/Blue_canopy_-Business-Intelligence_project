
DROP TABLE IF EXISTS Blue_canopy.gold.dim_campaign
SELECT ROW_NUMBER() OVER(ORDER BY campaign_id) campaign_key
      ,[campaign_id]
      ,[campaign_name]
      ,[campaign_type]
      ,[channel]
	  INTO Blue_canopy.gold.dim_campaign
  FROM [Blue_canopy].[silver].[campaigns]
