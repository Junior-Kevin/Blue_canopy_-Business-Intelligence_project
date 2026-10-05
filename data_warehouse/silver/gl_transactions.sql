DROP TABLE IF EXISTS silver.gl_transactions;
GO
WITH base AS (
    SELECT 
        [transaction_id],
        [account_code],
        CAST([date] AS DATE) AS transaction_date,
        CAST([amount] AS FLOAT) AS amount,
        LOWER([type]) AS transaction_type,
        CASE 
            WHEN store_id LIKE '%-DUP%' THEN LEFT(store_id, CHARINDEX('-DUP', store_id) - 1)
            ELSE store_id
        END AS store_id
    FROM [Blue_canopy].[bronze].[gl_transactions_raw]
    WHERE [transaction_id] IS NOT NULL
),

cleaned AS (
    SELECT 
        -- Core identifiers
        transaction_id,
        
        -- Parse account code (split code and name)
        LEFT(account_code, CHARINDEX('-', account_code) - 1) AS account_number,
        RIGHT(account_code, LEN(account_code) - CHARINDEX('-', account_code)) AS account_name,
        account_code,
        
        -- Clean store_id (handle -DUP suffix)
         store_id,
        -- Transaction date
        transaction_date,
        YEAR(transaction_date) AS transaction_year,
        MONTH(transaction_date) AS transaction_month,
        DATEPART(QUARTER, transaction_date) AS transaction_quarter,
        FORMAT(transaction_date, 'yyyy-MM') AS transaction_year_month,
        
        -- Amount (absolute value for calculations)
        amount,
        transaction_type,
        
        -- Signed amount (debit positive, credit negative for expense perspective)
        CASE 
            WHEN transaction_type = 'debit' THEN amount
            WHEN transaction_type = 'credit' THEN -amount
            ELSE 0
        END AS signed_amount_debit_view,
        
        -- Signed amount (credit positive, debit negative for revenue perspective)
        CASE 
            WHEN transaction_type = 'credit' THEN amount
            WHEN transaction_type = 'debit' THEN -amount
            ELSE 0
        END AS signed_amount_credit_view,
        
        -- Account category (derived from account number)
        CASE 
            WHEN LEFT(account_code, 1) = '1' THEN 'Assets'
            WHEN LEFT(account_code, 1) = '2' THEN 'Liabilities'
            WHEN LEFT(account_code, 1) = '3' THEN 'Equity'
            WHEN LEFT(account_code, 1) = '4' THEN 'Revenue'
            WHEN LEFT(account_code, 1) = '5' THEN 'Cost of Goods Sold'
            WHEN LEFT(account_code, 1) = '6' THEN 'Operating Expenses'
            WHEN LEFT(account_code, 1) = '7' THEN 'Other Income/Expense'
            ELSE 'Other'
        END AS account_category,
        
        -- Data quality flags
        CASE 
            WHEN amount <= 0 THEN 'Invalid amount'
            WHEN transaction_type NOT IN ('debit', 'credit') THEN 'Invalid transaction type'
            WHEN store_id IS NULL THEN 'Missing store'
            WHEN account_code IS NULL THEN 'Missing account'
            ELSE 'Valid'
        END AS quality_flag
        
    FROM base
)

SELECT 
    -- Surrogate key
    transaction_id AS gl_transaction_key,
    
    -- Identifiers
    transaction_id,
    account_code,
    account_number,
    account_name,
    account_category,
    store_id,
    
    -- Transaction details
    transaction_date,
    transaction_type,
    amount,
    signed_amount_debit_view,
    signed_amount_credit_view,
    
    -- Time attributes
    transaction_year,
    transaction_month,
    transaction_quarter,
    transaction_year_month,
    
    -- Quality
    quality_flag,
    
    -- Audit
    GETDATE() AS etl_load_date,
    'silver.gl_transactions' AS etl_source
    
INTO silver.gl_transactions
FROM cleaned
WHERE quality_flag = 'Valid'
ORDER BY transaction_date DESC, transaction_id
