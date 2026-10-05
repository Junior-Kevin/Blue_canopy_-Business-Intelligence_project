USE Blue_canopy;
GO

-- ============================================================
-- GOLD: gold.dim_gift_card_type
-- Small dimension describing the type of gift card event.
-- Static values derived from silver.gift_card_transactions.type.
-- ============================================================

DROP TABLE IF EXISTS gold.dim_gift_card_type;
GO

CREATE TABLE gold.dim_gift_card_type (
    gift_card_type_key   INT IDENTITY(1,1) PRIMARY KEY,
    transaction_type     NVARCHAR(50)  NOT NULL,
    transaction_category NVARCHAR(20)  NOT NULL,   -- 'Credit' or 'Debit'
    description          NVARCHAR(200) NULL
);
GO

INSERT INTO gold.dim_gift_card_type (transaction_type, transaction_category, description)
VALUES
    ('issue',      'Credit', 'Initial card load at issuance'),
    ('top_up',     'Credit', 'Card reloaded by customer'),
    ('redeem',     'Debit',  'Card used to pay for a purchase'),
    ('refund',     'Credit', 'Refund credited back to the card'),
    ('expiry',     'Debit',  'Unused balance expired'),
    ('adjustment', 'Credit', 'Manual adjustment by operations'),
    ('Unknown',    'Unknown','Placeholder for unrecognised types');
GO
