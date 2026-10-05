DROP TABLE IF EXISTS [gold].[dim_supplier];
SELECT 
 ROW_NUMBER() OVER(ORDER BY supplier_id,valid_from,valid_to) supplier_key
       ,[supplier_id]
      ,[valid_from]
      ,[valid_to]
      ,[supplier_name]
      ,[contact_person]
      ,[phone]
      ,[email]
      ,[payment_terms]
      ,[lead_time_days]
      ,[category]
      ,[tax_id]
INTO [gold].[dim_supplier]
FROM [Blue_canopy].[silver].[suppliers]
