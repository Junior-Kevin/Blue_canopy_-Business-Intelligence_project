DROP TABLE IF EXISTS gold.dim_campaigns 
SELECT ROW_NUMBER() OVER(ORDER BY campaign_id) campaign_key 
       ,[campaign_id]
       ,[campaign_name]
       ,[campaign_type]
       ,[channel]
 INTO gold.dim_campaigns 
 FROM [Blue_canopy].[silver].[campaigns]
