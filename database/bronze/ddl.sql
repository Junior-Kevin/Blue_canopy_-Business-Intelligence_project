/*
===============================================================================
DDL Script: Create Bronze Tables – Blue Canopy Kenya
===============================================================================
Script Purpose:
    This script creates the staging tables in the 'bronze' schema for the 
    Blue Canopy Kenya data warehouse. These tables serve as the 
    raw data landing zone before transformation.
    
    Key Features:
    - Drops existing tables if they exist to allow clean recreation
    - Creates all tables with column names matching CSV headers
    - All columns use NVARCHAR for maximum data type flexibility
    
Database Context:
    - Schema: bronze (raw, unprocessed data)
    - Data Types: All NVARCHAR for bronze layer flexibility
    
Usage Instructions:
    1. Run this script first to create the bronze schema and tables
    2. Use bronze.load_bronze stored procedure to populate data
    3. Ensure CSV files exist in the designated directory structure
    
Dependencies:
    - None (creates schema and tables independently)
===============================================================================
*/

-- ===========================================================================
-- SECTION 1: SCHEMA CREATION
-- ===========================================================================
USE Blue_canopy;
GO

-- Create the bronze schema if it doesn't exist
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'bronze')
BEGIN
    EXEC('CREATE SCHEMA bronze');
    PRINT 'Created schema: bronze';
END
ELSE
BEGIN
    PRINT 'Schema bronze already exists';
END
GO

-- ===========================================================================
-- SECTION 2: DROP AND CREATE TABLES (ALL COLUMNS NVARCHAR)
-- ===========================================================================

-- 1. competitors_raw
IF OBJECT_ID('bronze.competitors_raw','U') IS NOT NULL
    DROP TABLE bronze.competitors_raw;
CREATE TABLE bronze.competitors_raw (
    competitor_id     NVARCHAR(100) NULL,
    competitor_name   NVARCHAR(100) NULL,
    headquarters      NVARCHAR(100) NULL,
    estimated_stores  NVARCHAR(255) NULL   -- originally INT
);
PRINT 'Created table: bronze.competitors_raw';
GO

-- 2. competitor_quarterly_raw
IF OBJECT_ID('bronze.competitor_quarterly_raw','U') IS NOT NULL
    DROP TABLE bronze.competitor_quarterly_raw;
CREATE TABLE bronze.competitor_quarterly_raw (
    competitor_id   NVARCHAR(100) NULL,
    quarter         NVARCHAR(100) NULL,
    revenue_kes     NVARCHAR(255) NULL,    -- originally BIGINT
    market_share_pct NVARCHAR(255) NULL    -- originally FLOAT
);
PRINT 'Created table: bronze.competitor_quarterly_raw';
GO

-- 3. competitor_stores_raw
IF OBJECT_ID('bronze.competitor_stores_raw','U') IS NOT NULL
    DROP TABLE bronze.competitor_stores_raw;
CREATE TABLE bronze.competitor_stores_raw (
    competitor_store_id NVARCHAR(100) NULL,
    competitor_id       NVARCHAR(100) NULL,
    location            NVARCHAR(100) NULL,
    county              NVARCHAR(100) NULL,
    size_category       NVARCHAR(100) NULL
);
PRINT 'Created table: bronze.competitor_stores_raw';
GO

-- 4. crm_raw
IF OBJECT_ID('bronze.crm_raw','U') IS NOT NULL
    DROP TABLE bronze.crm_raw;
CREATE TABLE bronze.crm_raw (
    customer_id               NVARCHAR(100) NULL,
    valid_from                NVARCHAR(100) NULL,
    valid_to                  NVARCHAR(100) NULL,
    first_name                NVARCHAR(100) NULL,
    last_name                 NVARCHAR(100) NULL,
    gender                    NVARCHAR(100) NULL,
    birth_date                NVARCHAR(100) NULL,
    phone                     NVARCHAR(255) NULL,   -- originally FLOAT
    email                     NVARCHAR(100) NULL,
    county                    NVARCHAR(100) NULL,
    town                      NVARCHAR(100) NULL,
    customer_segment          NVARCHAR(100) NULL,
    acquisition_channel       NVARCHAR(100) NULL,
    registration_date         NVARCHAR(100) NULL,
    churn_date                NVARCHAR(100) NULL,
    loyalty_tier              NVARCHAR(100) NULL,
    communication_preferences NVARCHAR(100) NULL,
    feedback_score            NVARCHAR(255) NULL    -- originally FLOAT
);
PRINT 'Created table: bronze.crm_raw';
GO

-- 5. feedback_raw
IF OBJECT_ID('bronze.feedback_raw','U') IS NOT NULL
    DROP TABLE bronze.feedback_raw;
CREATE TABLE bronze.feedback_raw (
    feedback_id   NVARCHAR(100) NULL,
    customer_id   NVARCHAR(100) NULL,
    date          NVARCHAR(100) NULL,
    rating        NVARCHAR(255) NULL,   -- originally INT
    comment       NVARCHAR(500) NULL,
    category      NVARCHAR(100) NULL
);
PRINT 'Created table: bronze.feedback_raw';
GO

-- 6. service_interactions_raw
IF OBJECT_ID('bronze.service_interactions_raw','U') IS NOT NULL
    DROP TABLE bronze.service_interactions_raw;
CREATE TABLE bronze.service_interactions_raw (
    interaction_id          NVARCHAR(100) NULL,
    customer_id             NVARCHAR(100) NULL,
    interaction_date        NVARCHAR(100) NULL,
    channel                 NVARCHAR(100) NULL,
    issue_type              NVARCHAR(100) NULL,
    resolution_time_minutes NVARCHAR(255) NULL,   -- originally INT
    satisfaction_score      NVARCHAR(255) NULL    -- originally FLOAT
);
PRINT 'Created table: bronze.service_interactions_raw';
GO

-- 7. gl_transactions_raw
IF OBJECT_ID('bronze.gl_transactions_raw','U') IS NOT NULL
    DROP TABLE bronze.gl_transactions_raw;
CREATE TABLE bronze.gl_transactions_raw (
    transaction_id NVARCHAR(100) NULL,
    account_code   NVARCHAR(100) NULL,
    date           NVARCHAR(100) NULL,
    amount         NVARCHAR(255) NULL,   -- originally DECIMAL
    type           NVARCHAR(100) NULL,
    store_id       NVARCHAR(100) NULL
);
PRINT 'Created table: bronze.gl_transactions_raw';
GO

-- 8. store_daily_financials_raw
IF OBJECT_ID('bronze.store_daily_financials_raw','U') IS NOT NULL
    DROP TABLE bronze.store_daily_financials_raw;
CREATE TABLE bronze.store_daily_financials_raw (
    store_id            NVARCHAR(100) NULL,
    date                NVARCHAR(100) NULL,
    sales_kes           NVARCHAR(255) NULL,   -- originally FLOAT
    cost_of_goods_sold  NVARCHAR(255) NULL,   -- originally FLOAT
    gross_margin        NVARCHAR(255) NULL,   -- originally FLOAT
    operating_expenses  NVARCHAR(255) NULL,   -- originally FLOAT
    net_profit          NVARCHAR(255) NULL    -- originally FLOAT
);
PRINT 'Created table: bronze.store_daily_financials_raw';
GO

-- 9. gis_counties_raw
IF OBJECT_ID('bronze.gis_counties_raw','U') IS NOT NULL
    DROP TABLE bronze.gis_counties_raw;
CREATE TABLE bronze.gis_counties_raw (
    county          NVARCHAR(100) NULL,
    population      NVARCHAR(255) NULL,   -- originally INT
    avg_income_kes  NVARCHAR(255) NULL,   -- originally INT
    latitude        NVARCHAR(255) NULL,   -- originally FLOAT
    longitude       NVARCHAR(255) NULL    -- originally FLOAT
);
PRINT 'Created table: bronze.gis_counties_raw';
GO

-- 10. gis_locations_raw
IF OBJECT_ID('bronze.gis_locations_raw','U') IS NOT NULL
    DROP TABLE bronze.gis_locations_raw;
CREATE TABLE bronze.gis_locations_raw (
    location_id         NVARCHAR(100) NULL,
    county              NVARCHAR(100) NULL,
    town                 NVARCHAR(100) NULL,
    location_name       NVARCHAR(100) NULL,
    location_type       NVARCHAR(100) NULL,
    latitude            NVARCHAR(255) NULL,   -- originally FLOAT
    longitude           NVARCHAR(255) NULL,   -- originally FLOAT
    accessibility_score NVARCHAR(255) NULL    -- originally FLOAT
);
PRINT 'Created table: bronze.gis_locations_raw';
GO

-- 11. employee_shifts_raw
IF OBJECT_ID('bronze.employee_shifts_raw','U') IS NOT NULL
    DROP TABLE bronze.employee_shifts_raw;
CREATE TABLE bronze.employee_shifts_raw (
    shift_id       NVARCHAR(100) NULL,
    employee_id    NVARCHAR(100) NULL,
    store_id       NVARCHAR(100) NULL,
    shift_date     NVARCHAR(100) NULL,
    shift_type     NVARCHAR(100) NULL,
    start_time     NVARCHAR(100) NULL,
    end_time       NVARCHAR(100) NULL,
    hours_worked   NVARCHAR(255) NULL,   -- originally FLOAT
    overtime_hours NVARCHAR(255) NULL    -- originally INT
);
PRINT 'Created table: bronze.employee_shifts_raw';
GO

-- 12. hr_raw
IF OBJECT_ID('bronze.hr_raw','U') IS NOT NULL
    DROP TABLE bronze.hr_raw;
CREATE TABLE bronze.hr_raw (
    employee_id   NVARCHAR(100) NULL,
    valid_from    NVARCHAR(100) NULL,
    valid_to      NVARCHAR(100) NULL,
    first_name    NVARCHAR(100) NULL,
    last_name     NVARCHAR(100) NULL,
    gender        NVARCHAR(100) NULL,
    birth_date    NVARCHAR(100) NULL,
    hire_date     NVARCHAR(100) NULL,
    department    NVARCHAR(100) NULL,
    job_title     NVARCHAR(100) NULL,
    salary        NVARCHAR(255) NULL,   -- originally INT
    store_id      NVARCHAR(100) NULL,
    shift_pattern NVARCHAR(100) NULL
);
PRINT 'Created table: bronze.hr_raw';
GO

-- 13. time_tracking_raw
IF OBJECT_ID('bronze.time_tracking_raw','U') IS NOT NULL
    DROP TABLE bronze.time_tracking_raw;
CREATE TABLE bronze.time_tracking_raw (
    event_id    NVARCHAR(100) NULL,
    employee_id NVARCHAR(100) NULL,
    store_id    NVARCHAR(100) NULL,
    timestamp   NVARCHAR(100) NULL,
    event_type  NVARCHAR(100) NULL
);
PRINT 'Created table: bronze.time_tracking_raw';
GO

-- 14. inventory_movements_raw
IF OBJECT_ID('bronze.inventory_movements_raw','U') IS NOT NULL
    DROP TABLE bronze.inventory_movements_raw;
CREATE TABLE bronze.inventory_movements_raw (
    movement_id    NVARCHAR(100) NULL,
    movement_date  NVARCHAR(100) NULL,
    store_id       NVARCHAR(100) NULL,
    product_id     NVARCHAR(100) NULL,
    movement_type  NVARCHAR(100) NULL,
    quantity       NVARCHAR(255) NULL,   -- originally INT
    unit_cost_kes  NVARCHAR(255) NULL    -- originally FLOAT
);
PRINT 'Created table: bronze.inventory_movements_raw';
GO

-- 15. inventory_snapshots_raw
IF OBJECT_ID('bronze.inventory_snapshots_raw','U') IS NOT NULL
    DROP TABLE bronze.inventory_snapshots_raw;
CREATE TABLE bronze.inventory_snapshots_raw (
    snapshot_date      NVARCHAR(100) NULL,
    store_id           NVARCHAR(100) NULL,
    product_id         NVARCHAR(100) NULL,
    on_hand_quantity   NVARCHAR(255) NULL,   -- originally INT
    reorder_point      NVARCHAR(255) NULL,   -- originally FLOAT
    safety_stock       NVARCHAR(255) NULL    -- originally INT
);
PRINT 'Created table: bronze.inventory_snapshots_raw';
GO

-- 16. loyalty_transactions_raw
IF OBJECT_ID('bronze.loyalty_transactions_raw','U') IS NOT NULL
    DROP TABLE bronze.loyalty_transactions_raw;
CREATE TABLE bronze.loyalty_transactions_raw (
    transaction_id   NVARCHAR(100) NULL,
    customer_id      NVARCHAR(100) NULL,
    date             NVARCHAR(100) NULL,
    points_earned    NVARCHAR(255) NULL,   -- originally INT
    points_redeemed  NVARCHAR(255) NULL,   -- originally INT
    points_balance   NVARCHAR(255) NULL,   -- originally INT
    transaction_type NVARCHAR(100) NULL,
    order_id         NVARCHAR(100) NULL
);
PRINT 'Created table: bronze.loyalty_transactions_raw';
GO

-- 17. economic_raw
IF OBJECT_ID('bronze.economic_raw','U') IS NOT NULL
    DROP TABLE bronze.economic_raw;
CREATE TABLE bronze.economic_raw (
    county              NVARCHAR(100) NULL,
    year_month          NVARCHAR(100) NULL,
    gdp_growth_pct      NVARCHAR(255) NULL,   -- originally FLOAT
    inflation_pct       NVARCHAR(255) NULL,   -- originally FLOAT
    unemployment_pct    NVARCHAR(255) NULL,   -- originally FLOAT
    consumer_confidence NVARCHAR(255) NULL,   -- originally FLOAT
    retail_sales_index  NVARCHAR(255) NULL,   -- originally FLOAT
    fuel_price_kes      NVARCHAR(255) NULL,   -- originally DECIMAL
    usd_kes_rate        NVARCHAR(255) NULL    -- originally FLOAT
);
PRINT 'Created table: bronze.economic_raw';
GO

-- 18. campaigns_raw
IF OBJECT_ID('bronze.campaigns_raw','U') IS NOT NULL
    DROP TABLE bronze.campaigns_raw;
CREATE TABLE bronze.campaigns_raw (
    campaign_id      NVARCHAR(100) NULL,
    campaign_name    NVARCHAR(100) NULL,
    campaign_type    NVARCHAR(100) NULL,
    channel          NVARCHAR(100) NULL,
    start_date       NVARCHAR(100) NULL,
    end_date         NVARCHAR(100) NULL,
    budget_kes       NVARCHAR(255) NULL,   -- originally INT
    actual_spend_kes NVARCHAR(255) NULL,   -- originally INT
    discount_rate    NVARCHAR(255) NULL    -- originally DECIMAL
);
PRINT 'Created table: bronze.campaigns_raw';
GO

-- 19. promotions_raw
IF OBJECT_ID('bronze.promotions_raw','U') IS NOT NULL
    DROP TABLE bronze.promotions_raw;
CREATE TABLE bronze.promotions_raw (
    promotion_id   NVARCHAR(100) NULL,
	campaign_id   NVARCHAR(100) NULL,
    promotion_name NVARCHAR(100) NULL,
    start_date     NVARCHAR(100) NULL,
    end_date       NVARCHAR(100) NULL,
    discount_type  NVARCHAR(100) NULL,
    discount_value NVARCHAR(255) NULL   -- originally INT
);
PRINT 'Created table: bronze.promotions_raw';
GO

-- 20. promotion_products_raw
IF OBJECT_ID('bronze.promotion_products_raw','U') IS NOT NULL
    DROP TABLE bronze.promotion_products_raw;
CREATE TABLE bronze.promotion_products_raw (
    promotion_id NVARCHAR(100) NULL,
    product_id   NVARCHAR(100) NULL
);
PRINT 'Created table: bronze.promotion_products_raw';
GO

-- 21. goods_receipts_raw
IF OBJECT_ID('bronze.goods_receipts_raw','U') IS NOT NULL
    DROP TABLE bronze.goods_receipts_raw;
CREATE TABLE bronze.goods_receipts_raw (
    receipt_id        NVARCHAR(100) NULL,
    po_number         NVARCHAR(100) NULL,
    receipt_date      NVARCHAR(100) NULL,
    product_id        NVARCHAR(100) NULL,
    quantity_received NVARCHAR(255) NULL,   -- originally INT
    receiving_notes   NVARCHAR(100) NULL
);
PRINT 'Created table: bronze.goods_receipts_raw';
GO

-- 22. purchase_orders_raw
IF OBJECT_ID('bronze.purchase_orders_raw','U') IS NOT NULL
    DROP TABLE bronze.purchase_orders_raw;
CREATE TABLE bronze.purchase_orders_raw (
    po_number              NVARCHAR(100) NULL,
    order_date             NVARCHAR(100) NULL,
    supplier_id            NVARCHAR(100) NULL,
    expected_delivery_date NVARCHAR(100) NULL,
    status                 NVARCHAR(100) NULL,
    total_amount           NVARCHAR(255) NULL   -- originally DECIMAL
);
PRINT 'Created table: bronze.purchase_orders_raw';
GO

-- 23. purchase_order_lines_raw
IF OBJECT_ID('bronze.purchase_order_lines_raw','U') IS NOT NULL
    DROP TABLE bronze.purchase_order_lines_raw;
CREATE TABLE bronze.purchase_order_lines_raw (
    po_number        NVARCHAR(100) NULL,
    line_number      NVARCHAR(255) NULL,   -- originally INT
    product_id       NVARCHAR(100) NULL,
    quantity_ordered NVARCHAR(255) NULL,   -- originally INT
    unit_price       NVARCHAR(255) NULL,   -- originally DECIMAL
    line_total       NVARCHAR(255) NULL    -- originally DECIMAL
);
PRINT 'Created table: bronze.purchase_order_lines_raw';
GO

-- 24. products_raw
IF OBJECT_ID('bronze.products_raw','U') IS NOT NULL
    DROP TABLE bronze.products_raw;
CREATE TABLE bronze.products_raw (
    product_id          NVARCHAR(100) NULL,
    valid_from          NVARCHAR(100) NULL,
    valid_to            NVARCHAR(100) NULL,
    product_name        NVARCHAR(100) NULL,
    category            NVARCHAR(100) NULL,
    subcategory         NVARCHAR(100) NULL,
    brand               NVARCHAR(100) NULL,
    supplier_id         NVARCHAR(100) NULL,
    unit_cost_kes       NVARCHAR(255) NULL,   -- originally FLOAT
    retail_price_kes    NVARCHAR(255) NULL,   -- originally DECIMAL
    margin_percentage   NVARCHAR(255) NULL,   -- originally FLOAT
    introduction_date   NVARCHAR(100) NULL,
    discontinued_date   NVARCHAR(100) NULL,
    is_active           NVARCHAR(100) NULL
);
PRINT 'Created table: bronze.products_raw';
GO

-- 25. ecommerce_orders_raw
IF OBJECT_ID('bronze.ecommerce_orders_raw','U') IS NOT NULL
    DROP TABLE bronze.ecommerce_orders_raw;
CREATE TABLE bronze.ecommerce_orders_raw (
    order_id         NVARCHAR(100) NULL,
    order_date       NVARCHAR(100) NULL,
    customer_id      NVARCHAR(100) NULL,
    delivery_address NVARCHAR(100) NULL,
    delivery_fee     NVARCHAR(255) NULL,   -- originally INT
    payment_method   NVARCHAR(100) NULL,
    status           NVARCHAR(100) NULL,
    total_amount     NVARCHAR(255) NULL    -- originally DECIMAL
);
PRINT 'Created table: bronze.ecommerce_orders_raw';
GO

-- 26. ecommerce_order_lines_raw
IF OBJECT_ID('bronze.ecommerce_order_lines_raw','U') IS NOT NULL
    DROP TABLE bronze.ecommerce_order_lines_raw;
CREATE TABLE bronze.ecommerce_order_lines_raw (
    order_id      NVARCHAR(100) NULL,
    line_number   NVARCHAR(255) NULL,   -- originally INT
    product_id    NVARCHAR(100) NULL,
    quantity      NVARCHAR(255) NULL,   -- originally INT
    unit_price    NVARCHAR(255) NULL,   -- originally DECIMAL
    discount_rate NVARCHAR(255) NULL,   -- originally DECIMAL
    line_total    NVARCHAR(255) NULL    -- originally DECIMAL
);
PRINT 'Created table: bronze.ecommerce_order_lines_raw';
GO

-- 27. gift_cards_raw
IF OBJECT_ID('bronze.gift_cards_raw','U') IS NOT NULL
    DROP TABLE bronze.gift_cards_raw;
CREATE TABLE bronze.gift_cards_raw (
    card_number     NVARCHAR(100) NULL,
    issue_date      NVARCHAR(100) NULL,
    expiry_date     NVARCHAR(100) NULL,
    initial_balance NVARCHAR(255) NULL,   -- originally INT
    current_balance NVARCHAR(255) NULL    -- originally INT
);
PRINT 'Created table: bronze.gift_cards_raw';
GO

-- 28. gift_card_transactions_raw
IF OBJECT_ID('bronze.gift_card_transactions_raw','U') IS NOT NULL
    DROP TABLE bronze.gift_card_transactions_raw;
CREATE TABLE bronze.gift_card_transactions_raw (
    transaction_id NVARCHAR(100) NULL,
    card_number    NVARCHAR(100) NULL,
    date           NVARCHAR(100) NULL,
    amount         NVARCHAR(255) NULL,   -- originally INT
    type           NVARCHAR(100) NULL
);
PRINT 'Created table: bronze.gift_card_transactions_raw';
GO

-- 29. pos_line_items_raw
IF OBJECT_ID('bronze.pos_line_items_raw','U') IS NOT NULL
    DROP TABLE bronze.pos_line_items_raw;
CREATE TABLE bronze.pos_line_items_raw (
    transaction_id NVARCHAR(100) NULL,
    line_number    NVARCHAR(255) NULL,   -- originally INT
    product_id     NVARCHAR(100) NULL,
    quantity       NVARCHAR(255) NULL,   -- originally INT
    unit_price     NVARCHAR(255) NULL,   -- originally DECIMAL
    discount_rate  NVARCHAR(255) NULL,   -- originally DECIMAL
    line_total     NVARCHAR(255) NULL    -- originally DECIMAL
);
PRINT 'Created table: bronze.pos_line_items_raw';
GO

-- 30. pos_transactions_raw
IF OBJECT_ID('bronze.pos_transactions_raw','U') IS NOT NULL
    DROP TABLE bronze.pos_transactions_raw;
CREATE TABLE bronze.pos_transactions_raw (
    transaction_id    NVARCHAR(100) NULL,
    transaction_date  NVARCHAR(100) NULL,
    store_id          NVARCHAR(100) NULL,
    customer_id       NVARCHAR(100) NULL,
    cashier_id        NVARCHAR(100) NULL,
    payment_method    NVARCHAR(100) NULL,
    total_amount      NVARCHAR(255) NULL   -- originally DECIMAL
);
PRINT 'Created table: bronze.pos_transactions_raw';
GO

-- 31. returns_raw
IF OBJECT_ID('bronze.returns_raw','U') IS NOT NULL
    DROP TABLE bronze.returns_raw;
CREATE TABLE bronze.returns_raw (
    return_id               NVARCHAR(100) NULL,
    original_transaction_id NVARCHAR(100) NULL,
    return_date             NVARCHAR(100) NULL,
    product_id              NVARCHAR(100) NULL,
    quantity_returned       NVARCHAR(255) NULL,   -- originally INT
    refund_amount           NVARCHAR(255) NULL,   -- originally DECIMAL
    return_reason           NVARCHAR(100) NULL
);
PRINT 'Created table: bronze.returns_raw';
GO

-- 32. stores_raw
IF OBJECT_ID('bronze.stores_raw','U') IS NOT NULL
    DROP TABLE bronze.stores_raw;
CREATE TABLE bronze.stores_raw (
    store_id     NVARCHAR(100) NULL,
    valid_from   NVARCHAR(100) NULL,
    valid_to     NVARCHAR(100) NULL,
    store_name   NVARCHAR(100) NULL,
    county       NVARCHAR(100) NULL,
    town         NVARCHAR(100) NULL,
    format       NVARCHAR(100) NULL,
    size_sqm     NVARCHAR(255) NULL,   -- originally INT
    opening_date NVARCHAR(100) NULL,
    closing_date NVARCHAR(100) NULL,
    is_active    NVARCHAR(100) NULL
);
PRINT 'Created table: bronze.stores_raw';
GO

-- 33. suppliers_raw
IF OBJECT_ID('bronze.suppliers_raw','U') IS NOT NULL
    DROP TABLE bronze.suppliers_raw;
CREATE TABLE bronze.suppliers_raw (
    supplier_id     NVARCHAR(100) NULL,
    valid_from      NVARCHAR(100) NULL,
    valid_to        NVARCHAR(100) NULL,
    supplier_name   NVARCHAR(100) NULL,
    contact_person  NVARCHAR(100) NULL,
    phone           NVARCHAR(255) NULL,   -- originally BIGINT
    email           NVARCHAR(100) NULL,
    payment_terms   NVARCHAR(100) NULL,
    lead_time_days  NVARCHAR(255) NULL,   -- originally INT
    category        NVARCHAR(100) NULL,
    tax_id          NVARCHAR(100) NULL
);
PRINT 'Created table: bronze.suppliers_raw';
GO

-- ===========================================================================
-- SECTION 3: COMPLETION SUMMARY
-- ===========================================================================
PRINT '==============================================================';
PRINT 'BRONZE LAYER DDL CREATION COMPLETE';
PRINT '==============================================================';
PRINT '';
PRINT 'SUMMARY OF CREATED TABLES:';
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'bronze'
ORDER BY table_name;
PRINT '';
PRINT 'KEY DESIGN PRINCIPLES:';
PRINT '• All columns use NVARCHAR for maximum data type flexibility';
PRINT '• Data validation and type conversion happen in silver/gold layers';
PRINT '';
PRINT 'NEXT STEPS:';
PRINT '1. Run bronze.load_bronze stored procedure to populate tables';
PRINT '2. Ensure CSV files exist in the designated directory';
PRINT '3. Execute silver layer transformations after data loading';
PRINT '==============================================================';
GO
