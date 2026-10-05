USE Blue_canopy;
GO

-- ============================================================
-- GOLD: gold.fact_inventory_snapshots
-- Periodic snapshot fact. Grain: store × product × snapshot_date.
-- Measures: on_hand_quantity, reorder_point, safety_stock.
-- Source of truth for stock-level reporting.
-- ============================================================

DROP TABLE IF EXISTS gold.fact_inventory_snapshots;
GO

SELECT
    -- Surrogate key
    CONVERT(INT, ROW_NUMBER() OVER (
        ORDER BY snap.snapshot_date, snap.store_id, snap.product_id
    )) AS inventory_snapshot_sk,

    -- Foreign keys to dimensions
    ISNULL(ds.store_key,   -1) AS store_key,
    ISNULL(dp.product_key, -1) AS product_key,

    -- Date (kept as actual DATE per project convention)
    snap.snapshot_date,

    -- Measures (state at snapshot)
    snap.on_hand_quantity,
    snap.reorder_point,
    snap.safety_stock,

    -- Derived measures (state vs threshold)
    snap.on_hand_quantity - snap.reorder_point AS units_above_reorder,
    snap.on_hand_quantity - snap.safety_stock  AS units_above_safety,

    -- Ratio: stock as % of safety stock (capped at 999 to avoid inflation)
    CAST(CASE
        WHEN snap.safety_stock = 0 THEN NULL
        WHEN snap.on_hand_quantity * 100.0 / snap.safety_stock > 999 THEN 999
        ELSE snap.on_hand_quantity * 100.0 / snap.safety_stock
    END AS DECIMAL(9,2)) AS pct_of_safety_stock,

    -- Stock status (ready for slicers)
    CAST(CASE
        WHEN snap.on_hand_quantity < 0                    THEN 'Negative Stock'
        WHEN snap.on_hand_quantity = 0                    THEN 'Out of Stock'
        WHEN snap.on_hand_quantity < snap.safety_stock    THEN 'Below Safety Stock'
        WHEN snap.on_hand_quantity < snap.reorder_point   THEN 'Below Reorder Point'
        ELSE 'Healthy'
    END AS VARCHAR(30)) AS stock_status,

    -- Quality
    CAST(snap.quality_flag AS VARCHAR(50)) AS quality_flag

INTO gold.fact_inventory_snapshots
FROM silver.inventory_snapshots snap
LEFT JOIN gold.dim_store_bridge   ds ON snap.store_id   = ds.store_id
LEFT JOIN gold.dim_product_bridge dp ON snap.product_id = dp.product_id;
GO

CREATE NONCLUSTERED INDEX idx_fis_date 
    ON gold.fact_inventory_snapshots (snapshot_date);
CREATE NONCLUSTERED INDEX idx_fis_store_product 
    ON gold.fact_inventory_snapshots (store_key, product_key);
CREATE NONCLUSTERED INDEX idx_fis_status 
    ON gold.fact_inventory_snapshots (stock_status);
GO
