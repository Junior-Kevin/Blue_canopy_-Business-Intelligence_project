USE Blue_canopy;
GO

-- ============================================================
-- GOLD: gold.fact_gift_card_transactions
-- Grain: one row per gift card event (issue, top-up, redeem,
-- refund, expiry, adjustment).
-- Measures: signed amount (positive = credit, negative = debit).
-- Depends on: gold.dim_gift_card, gold.dim_gift_card_type.
-- ============================================================

DROP TABLE IF EXISTS gold.fact_gift_card_transactions;
GO

WITH enriched AS (
    SELECT
        gct.transaction_id,
        gct.card_number,
        gct.date                 AS transaction_date,
        gct.amount,
        gct.type                 AS transaction_type,
        gct.linked_transaction_id,

        -- Fall back to -1 keys for NULLs so fact table has no NULL FKs
        ISNULL(dgc.gift_card_sk,                    -1) AS gift_card_sk,
        ISNULL(dgc.customer_key,                    -1) AS customer_key,
        ISNULL(dgct.gift_card_type_key,             -1) AS gift_card_type_key

    FROM silver.gift_card_transactions gct
    LEFT JOIN gold.dim_gift_card      dgc  ON gct.card_number = dgc.card_number
    LEFT JOIN gold.dim_gift_card_type dgct ON gct.type        = dgct.transaction_type
)

SELECT
    -- Surrogate key for the fact row
    CONVERT(INT, ROW_NUMBER() OVER (
        ORDER BY transaction_date, transaction_id
    )) AS gift_card_transaction_sk,

    -- Degenerate dimension (business key of the event itself)
    transaction_id AS gift_card_transaction_id,

    -- Foreign keys to dimensions
    gift_card_sk,
    customer_key,
    gift_card_type_key,

    -- Date key / date (kept as actual date per your Gold preference)
    transaction_date,

    -- Link back to the sale that triggered this event (nullable)
    linked_transaction_id,

    -- Descriptive pass-through (optional but useful)
    transaction_type,

    -- Measure: signed amount
    amount,

    -- Audit
    GETDATE() AS etl_load_date,
    'gold.fact_gift_card_transactions' AS etl_source

INTO gold.fact_gift_card_transactions
FROM enriched;
GO

-- Indexes for common analytical access patterns
CREATE NONCLUSTERED INDEX idx_fgct_gift_card
    ON gold.fact_gift_card_transactions (gift_card_sk);

CREATE NONCLUSTERED INDEX idx_fgct_date
    ON gold.fact_gift_card_transactions (transaction_date);

CREATE NONCLUSTERED INDEX idx_fgct_linked_txn
    ON gold.fact_gift_card_transactions (linked_transaction_id);
GO
