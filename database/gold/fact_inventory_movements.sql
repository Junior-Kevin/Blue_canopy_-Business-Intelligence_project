USE Blue_canopy;
GO

-- ============================================================
-- GOLD: gold.fact_inventory_movements
-- Transaction fact. Grain: one row per stock movement.
-- Measures: quantity (signed), quantity_absolute, movement_value_kes.
-- ============================================================

DROP TABLE IF EXISTS gold.fact_inventory_movements;
GO

SELECT
    -- Surrogate key
    CONVERT(INT, ROW_NUMBER() OVER (
        ORDER BY mv.movement_date, mv.movement_id
    )) AS inventory_movement_sk,

    -- Degenerate dimensions (business keys, kept for traceability)
    mv.inventory_movement_key,
    mv.movement_id,

    -- Foreign keys to dimensions
    ISNULL(ds.store_key,             -1) AS store_key,
    ISNULL(dp.product_key,           -1) AS product_key,
    ISNULL(dmt.movement_type_key,    -1) AS movement_type_key,

    -- Date
    mv.movement_date,

    -- Descriptive pass-through
    mv.store_id,
    mv.product_id,
    mv.movement_type,

    -- Measures
    mv.quantity              AS quantity_signed,
    mv.quantity_absolute     AS quantity_absolute,
    mv.unit_cost_kes,
    mv.movement_value_kes,

    -- Running / cumulative measures (pass-through from Silver)
    mv.running_quantity,
    mv.cumulative_sum_by_product,
    mv.moving_sum_3_transactions,

    -- Derived: balance state at this movement
    CAST(CASE
        WHEN mv.running_quantity < 0 THEN 'Negative'
        WHEN mv.running_quantity = 0 THEN 'Zero'
        ELSE 'Positive'
    END AS VARCHAR(20)) AS balance_state,

    -- Quality/classification pass-through
    mv.inventory_status,
    mv.demand_velocity,
    mv.sign_validation_flag,
    mv.quality_flag,

    -- Time attributes
    mv.movement_year,
    mv.movement_month,
    mv.movement_quarter,
    mv.movement_year_month,
    mv.movement_month_name,

    -- Audit
    mv.etl_load_date,
    mv.etl_source

INTO gold.fact_inventory_movements
FROM silver.inventory_movements mv
LEFT JOIN gold.dim_store_bridge   ds  ON mv.store_id     = ds.store_id
LEFT JOIN gold.dim_product_bridge dp  ON mv.product_id   = dp.product_id
LEFT JOIN gold.dim_inventory_movement_type dmt
    ON mv.movement_type = dmt.movement_type;
GO

CREATE NONCLUSTERED INDEX idx_fim_date 
    ON gold.fact_inventory_movements (movement_date);
CREATE NONCLUSTERED INDEX idx_fim_store_product 
    ON gold.fact_inventory_movements (store_key, product_key);
CREATE NONCLUSTERED INDEX idx_fim_movement_type 
    ON gold.fact_inventory_movements (movement_type_key);
CREATE NONCLUSTERED INDEX idx_fim_balance_state 
    ON gold.fact_inventory_movements (balance_state);
GO
