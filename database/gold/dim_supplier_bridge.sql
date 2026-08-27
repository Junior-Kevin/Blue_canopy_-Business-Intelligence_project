DROP TABLE IF EXISTS gold.dim_supplier_bridge	
GO
SELECT 
		ROW_NUMBER() OVER( ORDER BY supplier_id)supplier_key
		,[supplier_id]
 INTO gold.dim_supplier_bridge
  FROM (
  SELECT 
		ROW_NUMBER() OVER(PARTITION BY supplier_id ORDER BY supplier_id) flag 
		,[supplier_id]

  FROM [Blue_canopy].[silver].[suppliers])t
  WHERE flag =1
