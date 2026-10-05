
DROP TABLE IF EXISTS gold.fact_marketing;
SELECT [marketing_key] = ROW_NUMBER() OVER( ORDER BY pr.promotion_id)
      ,dim_pro.promotion_key
	  ,promotion_start_date = pr.[start_date]
      ,promotion_end_date = pr.[end_date]
	  ,promotion_duration_days = pr.[campaign_duration_days]
      ,dim_ca.campaign_key
      ,campaign_start_date = ca.[start_date]
      ,campaign_end_date = ca.[end_date]
	  ,ca.[campaign_duration_days]
      ,pr.[discount_type]
      ,pr.[discount_value]
      ,pr.[is_active]
      ,pr.[days_until_start]
      ,pr.[days_since_ended]
      ,campaign_budget = ca.[budget_kes]
      ,campaign_budget_actual_spend= ca.[actual_spend_kes]
      ,campaign_budget_variance = ca.[variance]
  INTO gold.fact_marketing
  FROM [Blue_canopy].[silver].[promotions] pr
  LEFT JOIN [Blue_canopy].[silver].[campaigns] ca
  ON pr.campaign_id = ca.campaign_id
  LEFT JOIN [gold].[dim_promotions] dim_pro
  ON pr.promotion_id = dim_pro.promotion_id
  LEFT JOIN [gold].[dim_campaigns] dim_ca
  ON pr.campaign_id = dim_ca.campaign_id
