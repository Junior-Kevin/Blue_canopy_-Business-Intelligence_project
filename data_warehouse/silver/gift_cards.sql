
DROP TABLE IF EXISTS silver.gift_cards;
SELECT  [card_number]
       ,[customer_id]
      ,CAST([issue_date] AS DATE)  issue_date
      ,CAST([expiry_date] AS DATE)  expiry_date
      ,CAST([initial_balance] AS INT) initial_balance
      ,CAST([current_balance] AS INT) current_balance
      ,[transaction_ids]
	INTO silver.gift_cards
  FROM [Blue_canopy].[bronze].[gift_cards_raw]
