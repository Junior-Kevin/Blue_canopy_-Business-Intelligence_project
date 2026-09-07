DROP TABLE IF EXISTS Blue_canopy.silver.campaigns;
GO
WITH main AS
     (SELECT  [campaign_id]
      ,[campaign_name]
      ,[campaign_type]
      ,CASE WHEN [channel] IS NULL THEN 'Digital' ELSE channel END AS channel
      ,CAST([start_date] AS DATE) start_date 
      ,CAST([end_date] AS DATE ) end_date 
      ,CAST([budget_kes] AS INT) budget_kes 
      ,CAST([actual_spend_kes] AS INT) actual_spend_kes
      ,CAST([discount_rate] AS FLOAT) discount_rate
  FROM [Blue_canopy].[bronze].[campaigns_raw]
  WHERE campaign_id NOT LIKE '%DUP')
  SELECT [campaign_id]
      ,[campaign_name]
      ,[campaign_type]
      ,[channel]
      ,start_date 
      ,end_date 
	  ,campaign_duration_days = DATEDIFF(DAY,start_date,end_date)
      ,budget_kes 
      ,actual_spend_kes
	  ,variance= budget_kes - actual_spend_kes
      ,discount_rate
	  INTO Blue_canopy.silver.campaigns
	  FROM main
	  ORDER BY start_date
	  
