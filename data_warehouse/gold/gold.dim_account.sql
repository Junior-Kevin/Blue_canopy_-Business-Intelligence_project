USE Blue_canopy;
GO

-- ============================================================
-- GOLD: gold.dim_account
-- Chart of accounts dimension. One row per account.
-- ============================================================

DROP TABLE IF EXISTS gold.dim_account;
GO

WITH base AS (
    SELECT DISTINCT
        account_code,
        account_number,
        account_name,
        account_category
    FROM silver.gl_transactions
),
with_category AS (
    SELECT
        account_code,
        account_number,
        account_name,
        account_category,

        -- Coarser category for high-level reporting
        CASE
            WHEN account_category IN ('Assets', 'Liabilities', 'Equity') THEN 'Balance Sheet'
            WHEN account_category IN ('Revenue', 'Operating Expenses', 'Cost of Sales') THEN 'Income Statement'
            ELSE 'Other'
        END AS statement_section,

        -- Natural sign: 1 for debit-normal (Assets, Expenses), -1 for credit-normal (Liabilities, Revenue, Equity)
        CASE
            WHEN account_category IN ('Assets', 'Operating Expenses', 'Cost of Sales') THEN  1
            WHEN account_category IN ('Liabilities', 'Equity', 'Revenue')                THEN -1
            ELSE 1
        END AS normal_balance_sign
    FROM base
)

SELECT
    CONVERT(INT, ROW_NUMBER() OVER (ORDER BY account_number)) AS account_key,
    account_code,
    account_number,
    account_name,
    account_category,
    statement_section,
    normal_balance_sign,

    GETDATE() AS etl_load_date,
    'gold.dim_account' AS etl_source

INTO gold.dim_account
FROM with_category
UNION ALL
SELECT
    -1,                     -- Unknown key
    'UNKNOWN',
    0,
    'Unknown Account',
    'Unknown',
    'Other',
    1,
    GETDATE(),
    'gold.dim_account';
GO

CREATE NONCLUSTERED INDEX idx_dim_account_code
    ON gold.dim_account (account_code);
GO
