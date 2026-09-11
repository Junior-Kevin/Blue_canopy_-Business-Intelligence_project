DROP TABLE IF EXISTS silver.service_interactions;
GO
SELECT  [interaction_id]
      ,LEFT([customer_id],11) customer_id 
      ,CAST(CASE WHEN interaction_date = '2023-13-45' THEN 
	    '2023-12-25' ELSE interaction_date END AS DATE) interaction_date
      ,[channel]
      ,[issue_type]
      ,ABS(CAST([resolution_time_minutes] AS INT)) resolution_time_minutes
      ,ABS(CAST([satisfaction_score] AS FLOAT)) satisfaction_score
INTO silver.service_interactions
FROM [Blue_canopy].[bronze].[service_interactions_raw]
