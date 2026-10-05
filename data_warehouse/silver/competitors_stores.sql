USE Blue_canopy;
GO

DROP TABLE IF EXISTS silver.competitor_stores;
GO

SELECT
    [competitor_store_id],
    [competitor_id],
    [location],
    [county],
    [size_category],
    quality_flag = CAST(
        CASE
            WHEN [competitor_id] IS NULL
                 OR LTRIM(RTRIM([competitor_id])) = ''
                THEN 'Missing competitor ID'
            WHEN UPPER(LTRIM(RTRIM([size_category]))) NOT IN ('SMALL','MEDIUM','LARGE')
                 OR [size_category] IS NULL
                THEN 'Invalid size category'
            ELSE 'Valid'
        END AS NVARCHAR(50)),
    etl_load_date = SYSDATETIME(),
    etl_source    = CAST('silver.usp_Load_CompetitorStores' AS NVARCHAR(200))
INTO silver.competitor_stores
FROM [Blue_canopy].[bronze].[competitor_stores_raw];
GO
