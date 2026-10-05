DROP TABLE IF EXISTS gold.dim_promotions;
GO
SELECT 
      [promotion_key] = ROW_NUMBER() OVER(ORDER BY promotion_id)
      ,[promotion_id]
      ,[promotion_name]
      ,[promotion_status]
      ,promotion_length_tier = [campaign_length_tier]
      ,[discount_type]
      ,[discount_amount_or_percent]
      ,[discount_description]
      ,[is_active]
	INTO gold.dim_promotions
FROM [Blue_canopy].[silver].[promotions]
