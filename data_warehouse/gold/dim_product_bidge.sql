DROP TABLE IF EXISTS gold.dim_product_bridge;
GO
SELECT 
       ROW_NUMBER() OVER( ORDER BY product_id) product_key
	   ,[product_id]
INTO gold.dim_product_bridge
FROM (
SELECT 
       ROW_NUMBER() OVER(PARTITION BY product_id ORDER BY product_id) flag
	   ,[product_id]
  FROM [Blue_canopy].[silver].[products])T
  WHERE flag  = 1
