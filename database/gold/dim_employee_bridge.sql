
DROP TABLE IF EXISTS gold.dim_employee_bridge
SELECT 
   ROW_NUMBER() OVER(ORDER BY employee_id) employee_key,
   employee_id 
   INTO gold.dim_employee_bridge
   FROM (
SELECT 
    ROW_NUMBER() OVER(PARTITION BY employee_id ORDER BY employee_id) flag,
     [employee_id]
  FROM [Blue_canopy].[silver].[hr])t
  WHERE flag = 1
