DROP TABLE IF EXISTS silver.loyalty_transactions;
GO

WITH base AS (
    SELECT 
        [transaction_id],
        LEFT([customer_id], 11) AS customer_id,
        CAST(
            CASE 
                WHEN [date] = '2023-13-45' THEN '2023-12-25' 
                ELSE [date] 
            END AS DATE
        ) AS transaction_date,
        CAST([points_earned] AS INT) AS points_earned,
        ABS(CAST([points_redeemed] AS INT)) AS points_redeemed,
        CAST([points_balance] AS INT) AS points_balance,
        LOWER(TRIM([transaction_type])) AS transaction_type,
        CASE 
            WHEN order_id LIKE 'TXN%' THEN 
                CONCAT('TXN-', TRIM(SUBSTRING(order_id, CHARINDEX('-', order_id) + 1, 20)))
            ELSE order_id 
        END AS order_id
    FROM [Blue_canopy].[bronze].[loyalty_transactions_raw]
    WHERE [transaction_id] IS NOT NULL 
      AND [customer_id] IS NOT NULL
),

cleaned AS (
    SELECT 
        -- Core identifiers
        transaction_id,
        customer_id,
        
        -- Clean customer_id (remove -DUP if exists)
        CASE 
            WHEN customer_id LIKE '%-DUP%' THEN LEFT(customer_id, CHARINDEX('-DUP', customer_id) - 1)
            ELSE customer_id
        END AS customer_id_clean,
        
        -- Date handling
        transaction_date,
        YEAR(transaction_date)       AS transaction_year,
        MONTH(transaction_date)      AS transaction_month,
        DATEPART(QUARTER, transaction_date) AS transaction_quarter,
        FORMAT(transaction_date, 'yyyy-MM') AS transaction_year_month,
        
        -- Points
        points_earned,
        points_redeemed,   -- stored as positive
        points_balance,
        
        -- Signed net change (used for running balance)
        CASE 
            WHEN transaction_type = 'redeem' THEN -ABS(points_redeemed)
            ELSE points_earned
        END AS points_net_change,
        
        -- Transaction type standardization
        CASE 
            WHEN transaction_type IN ('earn', 'earning', 'earned', 'credit') THEN 'Earn'
            WHEN transaction_type IN ('redeem', 'redemption', 'redeemed', 'debit') THEN 'Redeem'
            WHEN points_earned < 0 THEN 'Adjustment (Negative)'
            WHEN points_redeemed > 0 AND transaction_type = 'earn' THEN 'Mixed - Review'
            ELSE 'Other'
        END AS transaction_type_clean,
        
        -- Order linkage
        order_id,
        CASE 
            WHEN order_id IS NULL OR order_id = '' THEN 'No linked order'
            WHEN order_id LIKE 'ECORD-%' THEN 'E-commerce order'
            WHEN order_id LIKE 'TXN-%' THEN 'POS transaction'
            ELSE 'Unknown source'
        END AS order_source_type,
        
        -- Points activity tier
        CASE 
            WHEN points_earned >= 1000 THEN 'High earner (1000+ points)'
            WHEN points_earned >= 500  THEN 'Medium earner (500-999 points)'
            WHEN points_earned >= 100  THEN 'Low earner (100-499 points)'
            WHEN points_earned > 0     THEN 'Small earner (1-99 points)'
            WHEN points_redeemed >= 1000 THEN 'High redemption (1000+ points)'
            ELSE 'No significant activity'
        END AS points_activity_tier,
        
        -- Customer point status
        CASE 
            WHEN points_balance >= 5000 THEN 'VIP - High points'
            WHEN points_balance >= 1000 THEN 'Active - Good points'
            WHEN points_balance >= 100  THEN 'Low points'
            WHEN points_balance > 0     THEN 'Minimal points'
            WHEN points_balance = 0 AND transaction_type = 'redeem' THEN 'Points exhausted'
            WHEN points_balance < 0     THEN 'Negative balance - Data error'
            ELSE 'No points'
        END AS customer_point_status,
        
        -- Base data quality flag (pre-running-balance)
        CASE 
            WHEN transaction_date > GETDATE() THEN 'Future date - Invalid'
            WHEN points_earned < 0 AND transaction_type = 'earn' AND points_redeemed = 0 
                THEN 'Negative earn - Possible adjustment'
            WHEN points_balance < 0 THEN 'Negative balance - Data error'
            WHEN transaction_type NOT IN ('earn', 'redeem') THEN 'Invalid transaction type'
            WHEN transaction_type = 'redeem' AND points_redeemed <= 0 THEN 'Invalid redemption amount'
            WHEN transaction_type = 'earn' AND points_earned <= 0 AND points_redeemed = 0 
                THEN 'No points movement'
            ELSE 'Valid'
        END AS quality_flag
        
    FROM base
),

-- Calculate the running points balance per customer (oldest -> newest)
with_running_balance AS (
    SELECT 
        *,
        SUM(points_net_change) OVER (
            PARTITION BY customer_id_clean 
            ORDER BY transaction_date ASC, transaction_id ASC,points_net_change 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS running_points_balance
    FROM cleaned
),

-- Apply final quality checks now that we have the running balance
finalised AS (
    SELECT 
        *,
        CASE 
            -- Preserve any pre-existing flag first
            WHEN quality_flag != 'Valid' THEN quality_flag
            
            -- Enforce business rule: customer cannot redeem more than they have earned
            WHEN transaction_type_clean = 'Redeem' 
                 AND running_points_balance < 0 
                THEN 'Redeem exceeds available balance'
            
            ELSE 'Valid'
        END AS quality_flag_final
    FROM with_running_balance
)

SELECT 
    -- Surrogate key
    ROW_NUMBER() OVER (ORDER BY customer_id_clean, transaction_date, transaction_id) AS loyalty_transaction_key,
    
    -- Identifiers
    transaction_id,
    customer_id_clean AS customer_id,
    order_id,
    
    -- Transaction details
    transaction_date,
    transaction_type_clean AS transaction_type,
    points_earned,
    points_redeemed,
    -- Points movement
    CASE 
        WHEN transaction_type_clean = 'Earn'   THEN points_earned
        WHEN transaction_type_clean = 'Redeem' THEN -points_redeemed
        ELSE points_net_change
    END AS points_change,
    running_points_balance,
    points_balance,                -- source-reported balance
    -- Metadata
    order_source_type,
    points_activity_tier,
    customer_point_status,
    
    -- Audit
    GETDATE() AS etl_load_date,
    'silver.loyalty_transactions' AS etl_source
    
INTO silver.loyalty_transactions
FROM finalised
WHERE quality_flag_final != 'Future date - Invalid';
