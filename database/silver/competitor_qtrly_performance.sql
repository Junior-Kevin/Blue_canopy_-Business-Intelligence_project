
DROP TABLE IF EXISTS silver.competitor_quarterly
GO
SELECT comp_qtr_key = ROW_NUMBER() OVER(ORDER BY [quarter])
       ,[competitor_id]
	  , store_name= [quarter]
	  ,ABS(CHECKSUM(NEWID()) % 47) + 1 AS county_key
      ,[quarter] =[revenue_kes]
	  ,CAST(SUBSTRING(market_share_pct,1,CHARINDEX(',',[market_share_pct])-1) AS INT) revenue_kes
	  ,CAST(SUBSTRING(market_share_pct,CHARINDEX(',',[market_share_pct])+1,4) AS FLOAT) market_share_pct
INTO silver.competitor_quarterly
FROM [Blue_canopy].[bronze].[competitor_quarterly_raw]
