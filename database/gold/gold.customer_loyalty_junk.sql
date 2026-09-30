
DROP TABLE IF EXISTS gold.customer_loyalty_junk;
GO
SELECT customer_loyalty_junk = ROW_NUMBER() OVER(ORDER BY [transaction_type]
      ,[order_source_type]
      ,[points_activity_tier]
      ,[customer_point_status]) 
  , transaction_type,order_source_type,points_activity_tier,customer_point_status
   INTO gold.customer_loyalty_junk
FROM (
SELECT flag = ROW_NUMBER() OVER(PARTITION BY transaction_type,
  order_source_type,points_activity_tier,customer_point_status
  ORDER BY transaction_type,
  order_source_type,points_activity_tier,customer_point_status
)
       ,[transaction_type]
      ,[order_source_type]
      ,[points_activity_tier]
      ,[customer_point_status]
  FROM [Blue_canopy].[silver].[loyalty_transactions]
  )g WHERE flag = 1
