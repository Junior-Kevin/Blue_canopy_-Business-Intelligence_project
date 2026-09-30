
USE Blue_canopy;
DROP TABLE IF EXISTS gold.fact_customer_layalty;
GO
SELECT  [loyalty_transaction_key]
      ,[transaction_id]
	  ,gdc.customer_key
      ,[order_id]
      ,[transaction_date]
      ,[points_earned]
      ,[points_redeemed]
      ,[points_change]
      ,[running_points_balance]
	  INTO gold.fact_customer_layalty
  FROM [Blue_canopy].[silver].[loyalty_transactions] slt
  LEFT JOIN [gold].[dim_customers] gdc
  ON  slt.customer_id = gdc.customer_id

