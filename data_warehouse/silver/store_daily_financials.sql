DROP TABLE IF EXISTS silver.store_daily_financials;
GO
SELECT [store_id]
      ,CAST([date] AS DATE) date
      ,CAST([sales_kes] AS FLOAT) sales_kes 
      ,CAST([cost_of_goods_sold] AS FLOAT) cost_of_goods_sold
      ,CAST([gross_margin] AS FLOAT) gross_margin
      ,CAST([operating_expenses] AS FLOAT) operating_expenses
      ,CAST([net_profit] AS FLOAT) net_profit
	  INTO silver.store_daily_financials
FROM [Blue_canopy].[bronze].[store_daily_financials_raw]
