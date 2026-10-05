DROP TABLE IF EXISTS silver.gift_card_transactions;
GO
WITH cards1 AS (
SELECT 
       [transaction_id]
      ,[card_number]
      ,CAST([date] AS DATE) date
      ,CAST([amount] AS INT)amount 
      ,SUBSTRING([type],1,CHARINDEX(',',type)-1) type
	  ,SUBSTRING(type,CHARINDEX(',',type)+1,20) linked_transaction_id
FROM [Blue_canopy].[bronze].[gift_card_transactions_raw]),
cards AS(
SELECT ROW_NUMBER() OVER(PARTITION BY card_number ORDER BY date) flag
       ,[transaction_id]
      ,[card_number]
      ,[date]
      ,[amount]
      ,[type]
      ,[linked_transaction_id]
  FROM cards1)
  SELECT 
       [transaction_id]
      ,[card_number]
      ,[date]
      ,CASE WHEN  (CASE WHEN flag = 1 AND type = 'issue' THEN 'issue'
	        WHEN flag !=1 AND type = 'issue' THEN 'top_up' 
		ELSE 'redeem' END) = 'redeem' THEN amount*-1 ELSE amount END as amount
	  ,CASE WHEN flag = 1 AND type = 'issue' THEN 'issue'
	        WHEN flag !=1 AND type = 'issue' THEN 'top_up' 
		ELSE 'redeem' END AS type
      ,[linked_transaction_id]
	  INTO silver.gift_card_transactions
	  FROM cards
	  ORDER BY 2,3
