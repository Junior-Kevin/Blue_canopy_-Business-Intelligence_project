DROP TABLE IF EXISTS silver.service_interactions;
GO
SELECT  [interaction_id]
      ,LEFT([customer_id],11) customer_id 
      ,CAST(CASE WHEN interaction_date = '2023-13-45' THEN 
	    '2023-12-25' ELSE interaction_date END AS DATE) interaction_date
      ,[channel]
	  , [rating_label]=  
	     CASE  WHEN ABS(CAST([satisfaction_score] AS FLOAT)) = 1 THEN 'very poor'
	           WHEN ABS(CAST([satisfaction_score] AS FLOAT)) = 2 THEN 'poor'
	           WHEN ABS(CAST([satisfaction_score] AS FLOAT)) = 3 THEN 'average'
			   WHEN ABS(CAST([satisfaction_score] AS FLOAT)) = 4 THEN 'good'
	           WHEN ABS(CAST([satisfaction_score] AS FLOAT)) = 4 THEN 'exellent'
		ELSE 'neutral' END
      ,[issue_type]
      ,ABS(CAST([resolution_time_minutes] AS INT)) resolution_time_minutes
      ,ABS(CAST([satisfaction_score] AS FLOAT)) satisfaction_score
INTO silver.service_interactions
FROM [Blue_canopy].[bronze].[service_interactions_raw]
