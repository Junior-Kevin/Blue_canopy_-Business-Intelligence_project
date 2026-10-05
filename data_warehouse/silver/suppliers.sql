DROP TABLE IF EXISTS silver.suppliers
GO
SELECT [supplier_id]
      ,CAST(CASE WHEN valid_from = '2023-13-45' 
	  THEN '2016-01-01' ELSE valid_from END AS DATE) [valid_from]
      ,CAST(CASE WHEN valid_to = '2023-13-45' THEN '2016-01-01' 
	             WHEN valid_to IS NULL THEN GETDATE() 
	             ELSE valid_to END AS DATE) [valid_to]
      ,[supplier_name]
      ,COALESCE([contact_person],supplier_name) contact_person
      ,REPLACE([phone],'+254','')  phone
      ,REPLACE([email],'contact',LOWER(LEFT(supplier_name,2))) email
      ,[payment_terms]
      ,CAST([lead_time_days] AS INT)lead_time_days
      ,[category]
      ,[tax_id]
  INTO silver.suppliers
  FROM [Blue_canopy].[bronze].[suppliers_raw]
  WHERE supplier_id NOT LIKE '%DUP'
  
