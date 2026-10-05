USE Blue_canopy;
GO

-- ============================================================
-- GOLD: gold.dim_inventory_movement_type
-- Categorical dimension describing each stock movement type.
-- ============================================================

DROP TABLE IF EXISTS gold.dim_inventory_movement_type;
GO

CREATE TABLE gold.dim_inventory_movement_type (
    movement_type_key  INT IDENTITY(1,1) PRIMARY KEY,
    movement_type      NVARCHAR(50) NOT NULL,
    direction          NVARCHAR(20) NOT NULL,   -- Inbound / Outbound / Adjustment
    affects_stock      BIT          NOT NULL,   -- Does this change on-hand quantity?
    description        NVARCHAR(200) NULL
);
GO

INSERT INTO gold.dim_inventory_movement_type 
    (movement_type, direction, affects_stock, description)
VALUES
    ('RECEIPT',      'Inbound',    1, 'Goods received from supplier or warehouse'),
    ('TRANSFER_IN',  'Inbound',    1, 'Stock transferred in from another store'),
    ('RETURN',       'Inbound',    1, 'Customer return restocked'),
    ('SALE',         'Outbound',   1, 'Stock sold to a customer'),
    ('TRANSFER_OUT', 'Outbound',   1, 'Stock transferred out to another store'),
    ('DAMAGE',       'Outbound',   1, 'Stock written off due to damage'),
    ('LOSS',         'Outbound',   1, 'Stock lost or stolen'),
    ('ADJUSTMENT',   'Adjustment', 1, 'Manual stock count adjustment (positive or negative)'),
    ('Unknown',      'Unknown',    0, 'Placeholder for unrecognised movement types');
GO
