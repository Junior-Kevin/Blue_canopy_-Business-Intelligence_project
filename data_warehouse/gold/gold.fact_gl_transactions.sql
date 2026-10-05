USE Blue_canopy;
GO

-- ============================================================
-- GOLD: gold.fact_gl_transactions
-- Grain: one row per general-ledger journal entry line.
-- Measure: signed_amount_debit_view (debits positive, credits negative).
-- ============================================================

DROP TABLE IF EXISTS gold.fact_gl_transactions;
GO

SELECT
    -- Surrogate key
    CONVERT(INT, ROW_NUMBER() OVER (
        ORDER BY glt.transaction_date, glt.transaction_id, glt.gl_transaction_key
    )) AS gl_transaction_sk,

    -- Degenerate dimension (business key)
    glt.transaction_id,
    glt.gl_transaction_key,

    -- Foreign keys
    ISNULL(ds.store_key,   -1) AS store_key,
    ISNULL(da.account_key, -1) AS account_key,

    -- Dates
    glt.transaction_date,

    -- Descriptive pass-through
    glt.transaction_type,       -- 'debit' or 'credit'

    -- Measures
    glt.amount,                             -- unsigned original
    glt.signed_amount_debit_view,           -- primary measure
    glt.signed_amount_credit_view,          -- kept for reconciliation

    -- Audit
    GETDATE() AS etl_load_date,
    'gold.fact_gl_transactions' AS etl_source

INTO gold.fact_gl_transactions
FROM silver.gl_transactions glt
LEFT JOIN gold.dim_store_bridge ds ON glt.store_id    = ds.store_id
LEFT JOIN gold.dim_account da ON glt.account_code = da.account_code;
GO

CREATE NONCLUSTERED INDEX idx_fglt_date
    ON gold.fact_gl_transactions (transaction_date);
GO

CREATE NONCLUSTERED INDEX idx_fglt_store
    ON gold.fact_gl_transactions (store_key);
GO

CREATE NONCLUSTERED INDEX idx_fglt_account
    ON gold.fact_gl_transactions (account_key);
GO

CREATE NONCLUSTERED INDEX idx_fglt_txn
    ON gold.fact_gl_transactions (transaction_id);
GO
