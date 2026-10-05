DROP TABLE IF EXISTS silver.inventory_movements;

SELECT  [movement_id]
	   ,CAST(CASE WHEN movement_date = '2023-13-45' THEN '2023-12-25'
	       ELSE movement_date END AS DATE) movement_date
      ,CASE 
            WHEN store_id LIKE '%-DUP%' THEN LEFT(store_id, CHARINDEX('-DUP', store_id) - 1)
            ELSE store_id
        END AS store_id
      ,CASE WHEN product_id LIKE '%DUP' THEN LEFT(product_id,9) ELSE product_id END AS product_id
      ,LOWER([movement_type]) movement_type
      ,CAST([quantity] AS INT) quantity 
      ,CAST([unit_cost_kes] AS FLOAT)  unit_cost_kes
	  INTO silver.inventory_movements
  FROM [Blue_canopy].[bronze].[inventory_movements_raw]
