USE Blue_canopy;
GO

-- ============================================================
-- GOLD: gold.dim_gift_card
-- One row per gift card. Descriptive attributes only.
-- NOTE: The Silver column `transactions` (comma-separated list)
-- is deliberately EXCLUDED — it is a denormalized string that
-- duplicates what fact_gift_card_transactions already holds.
-- ============================================================

DROP TABLE IF EXISTS gold.dim_gift_card;
GO

WITH base AS (
    SELECT
        gc.card_number,
        gc.customer_id,
        gc.issue_date,
        gc.expiry_date,
        gc.initial_balance,
        gc.current_balance,

        -- Derived: card lifecycle status
        CASE
            WHEN gc.current_balance <= 0                THEN 'Fully Redeemed'
            WHEN gc.expiry_date < CAST(GETDATE() AS DATE) THEN 'Expired'
            WHEN gc.issue_date  > CAST(GETDATE() AS DATE) THEN 'Not Yet Issued'
            ELSE 'Active'
        END AS card_status,

        -- Coarser category for slicers
        CASE
            WHEN gc.current_balance <= 0                THEN 'Closed'
            WHEN gc.expiry_date < CAST(GETDATE() AS DATE) THEN 'Closed'
            ELSE 'Open'
        END AS card_status_category,

        -- Useful derived metrics for reporting
        DATEDIFF(DAY, gc.issue_date,  gc.expiry_date)     AS card_validity_days,
        DATEDIFF(DAY, gc.issue_date,  CAST(GETDATE() AS DATE)) AS card_age_days,
        gc.initial_balance - gc.current_balance           AS balance_consumed,
        CAST(
            CASE 
                WHEN gc.initial_balance = 0 THEN 0
                ELSE (gc.initial_balance - gc.current_balance) * 100.0 / gc.initial_balance
            END AS DECIMAL(9,2)
        )                                                  AS pct_balance_consumed

    FROM silver.gift_cards gc
)

SELECT
    -- Surrogate key
    CONVERT(INT, ROW_NUMBER() OVER (ORDER BY card_number)) AS gift_card_sk,

    -- Business key
    card_number,

    -- Foreign key to dim_customer (resolved via business key)
    dc.customer_key,

    -- Descriptive attributes
    base.customer_id,              -- kept for traceability
    issue_date,
    expiry_date,
    initial_balance,
    current_balance,
    card_status,
    card_status_category,
    card_validity_days,
    card_age_days,
    balance_consumed,
    pct_balance_consumed,

    -- Audit
    GETDATE() AS etl_load_date,
    'gold.dim_gift_card' AS etl_source

INTO gold.dim_gift_card
FROM base
LEFT JOIN gold.dim_customers dc
    ON base.customer_id = dc.customer_id;
GO

CREATE NONCLUSTERED INDEX idx_dim_gift_card_card_number
    ON gold.dim_gift_card (card_number);
GO
