DROP TABLE IF EXISTS gold.fact_customer_experience;
GO
WITH main AS (
SELECT  [interaction_id]
       ,[customer_key]
	   ,[cst_exp_junk_key]
       ,[interaction_date]
	   ,rating = [satisfaction_score]
  FROM [Blue_canopy].[silver].[service_interactions] si
  LEFT JOIN [Blue_canopy].[gold].[dim_customers] dc
  ON si.customer_id = dc. customer_id
  LEFT JOIN [Blue_canopy].[gold].[dim_customer_exp_junk] cuj
  ON si.channel = cuj.channel
    AND si.rating_label = cuj.rating_label
	AND si.issue_type = cuj.issue_type
  UNION ALL
SELECT 
       [interaction_id] = [feedback_id]
      ,[customer_key]
	  ,cuj.[cst_exp_junk_key]
      ,[interaction_date]=[feedback_date] 
	  ,[rating]
  FROM [Blue_canopy].[silver].[feedback] sf
  LEFT JOIN [Blue_canopy].[gold].[dim_customers] dc
  ON sf.customer_id = dc. customer_id
  LEFT JOIN [Blue_canopy].[gold].[dim_customer_exp_junk] cuj
  ON 'phone' = cuj.channel
    AND sf.rating_label = cuj.rating_label
	AND sf.category = cuj.issue_type
  )
  SELECT 
       customer_experience_key = ROW_NUMBER() OVER(ORDER BY interaction_date,interaction_id) 
       ,interaction_id
	   ,customer_key
	   ,cst_exp_junk_key
	   ,interaction_date
	   ,rating
 INTO gold.fact_customer_experience
 FROM main
