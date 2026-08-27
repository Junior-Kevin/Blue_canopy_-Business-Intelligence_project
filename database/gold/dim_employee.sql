USE Blue_canopy;
GO
DROP TABLE IF EXISTS  gold.dim_employee;
SELECT ROW_NUMBER() OVER(ORDER BY hr.employee_id) employee_sk
      ,hr.[employee_id]
	  ,eb.employee_key
	  ,[full_name]
      ,[display_name]
      ,email=[generated_email]
      ,[gender]
      ,[job_title]
      ,CASE
	      WHEN store_id IS NULL THEN 'HQ' ELSE
		  SUBSTRING(store_id,1,9) 
	   END store_id
      ,[valid_from]
      ,[birth_date]
	  ,[age]
	  ,[age_band]
      ,[generation]
      ,[hire_date]
      ,[salary]
	  ,[salary_band]
      ,[salary_equity_flag]
      ,[education_level]
      ,[tenure_days]
      ,[tenure_months]
      ,[tenure_years]
      ,[tenure_band]
      ,[retention_risk]
      ,[employment_status]
      ,[contract_length_months]
      ,[contract_type]
      ,[department]
      ,[department_category]
      ,[job_level]
      ,[is_manager]
      ,[hire_season]
      ,[years_since_hire]
      ,[hire_cohort]
	 INTO gold.dim_employee
  FROM [Blue_canopy].[silver].[hr] hr
  LEFT JOIN [gold].[dim_employee_bridge] eb
  ON hr.employee_id = eb.employee_id
