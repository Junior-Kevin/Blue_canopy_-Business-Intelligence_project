
DROP TABLE IF EXISTS marketing_factless_fact;
SELECT promo_factless_fact_key = ROW_NUMBER() OVER(ORDER BY pr.promotion_id)
      ,dim_pro.promotion_key
      ,pb.product_key
	  INTO gold.marketing_factless_fact
FROM [Blue_canopy].[silver].[promotion_products] pr
LEFT JOIN [gold].[dim_promotions] dim_pro
ON pr.promotion_id = dim_pro.promotion_id
LEFT JOIN [gold].[dim_product_bridge] pb
ON pr.product_id = pb.product_id
