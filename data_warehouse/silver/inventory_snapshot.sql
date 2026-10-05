
DROP TABLE IF EXISTS silver.inventory_snapshots;
GO

SELECT ROW_NUMBER() OVER(ORDER BY snapshot_date,store_id,product_id ) inventory_key
,snapshot_date,store_id,product_id,on_hand_quantity,reorder_point,safety_stock
INTO silver.inventory_snapshots
FROM(
SELECT  
  	  CAST(CASE WHEN snapshot_date = '2023-13-45' THEN '2023-12-25'
	        ELSE snapshot_date END AS DATE) snapshot_date
      ,CASE 
            WHEN store_id LIKE '%-DUP%' THEN LEFT(store_id, CHARINDEX('-DUP', store_id) - 1)
            ELSE store_id
        END AS store_id
      ,CASE WHEN product_id LIKE '%DUP' THEN LEFT(product_id,9) ELSE product_id END AS product_id
      ,CAST([on_hand_quantity] AS INT) on_hand_quantity 
      ,CAST([reorder_point] AS FLOAT)reorder_point 
      ,CAST([safety_stock] AS INT) safety_stock
  FROM [Blue_canopy].[bronze].[inventory_snapshots_raw]
  WHERE snapshot_date NOT LIKE '%DUP')t

