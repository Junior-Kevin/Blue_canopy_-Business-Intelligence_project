DROP TABLE IF EXISTS Blue_canopy.gold.dim_customers;
GO
SELECT  ROW_NUMBER() OVER(order by registration_date) customer_key
      ,crm.[customer_id]
      ,[full_name]
      ,[gender]
      ,[birth_date]
	  ,generation
      ,[age]
      ,[age_band]
      ,[phone]
	  ,[home_county]
      ,[primary_store_id]
      ,[town]
      ,[customer_segment]
      ,[acquisition_channel]
      ,[registration_date]
      ,[churn_date]
      ,[loyalty_tier]
      ,[communication_preferences]
      ,[feedback_score]
      ,[is_churned]
      ,[tenure_days]
      ,[tenure_months]
      ,[tenure_band]
   INTO gold.dim_customers
   FROM [Blue_canopy].[silver].[crm] crm 
