USE Blue_canopy;
GO

-- ============================================================
-- GOLD: gold.dim_product
-- Star-schema product dimension.
-- All business logic (cleaning, fallbacks, date fixes) is in
-- silver.products. This script only generates the surrogate
-- key and attaches the bridge key.
-- ============================================================

DROP TABLE IF EXISTS gold.dim_product;
GO

WITH main AS (
    SELECT
        -- Surrogate key: generated here in Gold
        CONVERT(INT, ROW_NUMBER() OVER (
            ORDER BY sp.product_id, sp.valid_from
        )) AS product_sk,

        pb.product_key,

        sp.product_id,
        sp.product_name,
        sp.brand,
        sp.category,
        sp.subcategory,
        sp.supplier_id,
        sp.unit_cost_kes,
        sp.retail_price_kes,
        sp.margin_percentage,
        sp.margin_band,
        sp.introduction_date,
        sp.valid_from,
        sp.valid_to,
        sp.discontinued_date,
        sp.is_active,
        sp.is_current_version
    FROM silver.products sp
    LEFT JOIN gold.dim_product_bridge pb
        ON sp.product_id = pb.product_id
)

SELECT
    product_sk,
    product_key,
    product_id,
    product_name,
    brand,
    category,
    subcategory,
    supplier_id,
    unit_cost_kes,
    retail_price_kes,
    margin_percentage,
    margin_band,
    introduction_date,
    valid_from,
    valid_to,
    discontinued_date,
    is_active,
    is_current_version
INTO gold.dim_product
FROM main
ORDER BY product_sk;
GO

-- Columnstore index for analytical workloads
CREATE NONCLUSTERED COLUMNSTORE INDEX idx_product_product_id
    ON gold.dim_product (product_id);
GO
