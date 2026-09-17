USE Blue_canopy;
GO
DROP TABLE IF EXISTS gold.dim_customer_exp_junk;
GO
WITH main AS (
SELECT 
       [channel]
	  ,[rating_label]  
      ,[issue_type]
  FROM [Blue_canopy].[silver].[service_interactions]
  UNION ALL
SELECT 
	   [channel] = 'phone'
      ,[rating_label]
      ,issue_type = [category] 
  FROM [Blue_canopy].[silver].[feedback]), 
  flag AS (
  SELECT 
     ROW_NUMBER() OVER(PARTITION BY channel,rating_label,issue_type
	 ORDER BY channel,rating_label,issue_type) flag
	 ,channel
	 ,rating_label
	 ,issue_type
  FROM main)
  SELECT 
  cst_exp_junk_key =  ROW_NUMBER() OVER(ORDER BY channel,rating_label,issue_type),
  channel,rating_label,issue_type
  INTO gold.dim_customer_exp_junk
  FROM flag  WHERE flag = 1
