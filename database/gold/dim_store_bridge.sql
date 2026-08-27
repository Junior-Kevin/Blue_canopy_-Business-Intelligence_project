 USE Blue_canopy;
GO
DROP TABLE IF EXISTS gold.dim_store_bridge;
 
 SELECT ROW_NUMBER() OVER(ORDER BY store_id ) store_key
,store_id 
INTO gold.dim_store_bridge
FROM(
		 SELECT ROW_NUMBER() OVER(PARTITION BY store_id ORDER BY store_id ) store_key,
		 store_id FROM  [gold].[dim_store])T
 WHERE store_key = 1 

