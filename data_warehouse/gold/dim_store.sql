USE Blue_canopy;
GO
DROP TABLE IF EXISTS gold.dim_store;
GO
SELECT 
      ss.store_key AS store_sk
     ,sb.[store_key]
     ,ss.[store_id]
     ,[valid_from]
     ,[valid_to]
     ,[store_name]
     ,[county]
     ,[town]
     ,[format]
     ,[size_sqm]
     ,[opening_date]
     ,[closing_date]
     ,[is_active]
     INTO gold.dim_store
FROM [Blue_canopy].[silver].[stores] ss
LEFT JOIN [Blue_canopy].gold.dim_store_bridge sb
ON ss.store_id = sb.store_id;
