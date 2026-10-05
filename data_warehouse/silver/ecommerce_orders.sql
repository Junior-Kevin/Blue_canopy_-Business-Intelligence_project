-- ============================================================
-- ETL: Bronze to Silver - Ecommerce Orders
-- Description: Cleanse and transform raw ecommerce order data
-- Author: [Your Name]
-- Date: 2026-07-17
-- Version: 2.0 (Preserves ALL rows with ABS for negatives)
-- ============================================================

USE Blue_canopy;
GO

-- ============================================================
-- 1. Drop existing table if it exists
-- ============================================================
IF OBJECT_ID('silver.ecommerce_orders', 'U') IS NOT NULL
BEGIN
    DROP TABLE IF EXISTS silver.ecommerce_orders;
END
GO

-- ============================================================
-- 2. Create table with proper structure and constraints
-- ============================================================
CREATE TABLE silver.ecommerce_orders (
    -- Surrogate Key
    ecommerce_key INT IDENTITY(1,1) PRIMARY KEY CLUSTERED,
    
    -- Business Keys
    order_id VARCHAR(50) NOT NULL,
    
    -- Date/Time Dimensions
    order_date DATE NOT NULL,
    order_time TIME(0) NOT NULL,
    
    -- Customer Information
    customer_id VARCHAR(50) NOT NULL,
    delivery_address VARCHAR(500) NOT NULL,
    
    -- Order Financials
    delivery_fee DECIMAL(18,2) NOT NULL DEFAULT 0,
    payment_method VARCHAR(50) NOT NULL,
    order_status VARCHAR(50) NULL,
    amount DECIMAL(18,2) NOT NULL,
    
    -- Audit Columns
    created_date DATETIME2 DEFAULT GETDATE() NOT NULL,
    modified_date DATETIME2 DEFAULT GETDATE() NOT NULL,
    data_load_date DATE DEFAULT CAST(GETDATE() AS DATE) NOT NULL,
    source_system VARCHAR(50) DEFAULT 'bronze.ecommerce_orders_raw' NOT NULL,
    etl_batch_id UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL
);
GO

-- ============================================================
-- 3. Add CHECK constraints
-- ============================================================
ALTER TABLE silver.ecommerce_orders
ADD CONSTRAINT CK_ecommerce_amount_positive 
    CHECK (amount >= 0);
GO

ALTER TABLE silver.ecommerce_orders
ADD CONSTRAINT CK_ecommerce_delivery_fee_positive 
    CHECK (delivery_fee >= 0);
GO

ALTER TABLE silver.ecommerce_orders
ADD CONSTRAINT CK_ecommerce_order_date_valid 
    CHECK (order_date <= CAST(GETDATE() AS DATE));
GO

-- ============================================================
-- 4. Create indexes for performance
-- ============================================================

-- Non-clustered indexes for query performance
CREATE NONCLUSTERED INDEX idx_ecommerce_order_id 
    ON silver.ecommerce_orders (order_id);
GO

CREATE NONCLUSTERED INDEX idx_ecommerce_order_date 
    ON silver.ecommerce_orders (order_date);
GO

CREATE NONCLUSTERED INDEX idx_ecommerce_customer_id 
    ON silver.ecommerce_orders (customer_id);
GO

CREATE NONCLUSTERED INDEX idx_ecommerce_payment_method 
    ON silver.ecommerce_orders (payment_method);
GO

CREATE NONCLUSTERED INDEX idx_ecommerce_order_status 
    ON silver.ecommerce_orders (order_status);
GO

-- Composite index for common query patterns
CREATE NONCLUSTERED INDEX idx_ecommerce_date_customer 
    ON silver.ecommerce_orders (order_date, customer_id) 
    INCLUDE (amount, payment_method, order_status);
GO

-- ============================================================
-- 5. Data transformation and insertion (Preserves ALL rows)
-- ============================================================

DECLARE @batch_id UNIQUEIDENTIFIER = NEWID();
DECLARE @start_time DATETIME2 = GETDATE();

WITH pattern_analysis AS (
    SELECT 
        order_id,
        order_date,
        customer_id,
        delivery_address,
        payment_method,
        status,
        total_amount,
        -- Count commas in total_amount
        LEN(total_amount) - LEN(REPLACE(total_amount, ',', '')) AS comma_count,
        -- Check if payment_method is numeric (delivery_fee)
        TRY_CAST(payment_method AS INT) AS payment_method_numeric,
        -- Check if status is numeric (delivery_fee)
        TRY_CAST(status AS INT) AS status_numeric
    FROM [Blue_canopy].[bronze].[ecommerce_orders_raw]
    -- DO NOT filter out any rows - keep ALL data
),
split_data AS (
    SELECT 
        p.*,
        value,
        ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY (SELECT NULL)) AS position
    FROM pattern_analysis p
    CROSS APPLY STRING_SPLIT(
        CASE 
            WHEN p.total_amount IS NULL OR p.total_amount = '' 
            THEN 'NULL,NULL,NULL'  -- Use 3 placeholders to handle all patterns
            ELSE p.total_amount 
        END, 
        ','
    )
),
final_data AS (
    SELECT 
        order_id,
        order_date,
        customer_id,
        delivery_address,
        comma_count,
        payment_method_numeric,
        status_numeric,
        -- delivery_fee logic - use ABS to handle negatives
        ABS(
            CASE 
                -- Pattern 1: payment_method column contains delivery_fee (numeric)
                WHEN comma_count = 1 AND payment_method_numeric IS NOT NULL 
                THEN payment_method_numeric
                -- Pattern 2: status column contains delivery_fee (numeric)
                WHEN comma_count = 2 AND status_numeric IS NOT NULL 
                THEN status_numeric
                -- Pattern 3: try both
                WHEN comma_count = 0 AND payment_method_numeric IS NOT NULL
                THEN payment_method_numeric
                ELSE 0
            END
        ) AS delivery_fee,
        
        -- payment_method logic
        CASE 
            -- Pattern 1: status column contains payment_method
            WHEN comma_count = 1 
            THEN ISNULL(TRIM(status), 'Unknown')
            -- Pattern 2: position 1 = payment_method
            WHEN comma_count = 2 
            THEN ISNULL(TRIM(MAX(CASE WHEN position = 1 THEN value END)), 'Unknown')
            -- Pattern 0: payment_method from source
            WHEN comma_count = 0 
            THEN ISNULL(TRIM(payment_method), 'Unknown')
            ELSE 'Unknown'
        END AS payment_method,
        
        -- status logic
        CASE 
            -- Pattern 1: position 1 = status
            WHEN comma_count = 1 
            THEN TRIM(MAX(CASE WHEN position = 1 THEN value END))
            -- Pattern 2: position 2 = status
            WHEN comma_count = 2 
            THEN TRIM(MAX(CASE WHEN position = 2 THEN value END))
            -- Pattern 0: status from source
            WHEN comma_count = 0 
            THEN TRIM(status)
            ELSE NULL
        END AS order_status,
        
        -- amount logic - ALWAYS use ABS to handle negatives
        ABS(
            CASE 
                -- Pattern 1: position 2 = amount
                WHEN comma_count = 1 
                THEN ISNULL(TRY_CAST(MAX(CASE WHEN position = 2 THEN value END) AS DECIMAL(18,2)), 0)
                -- Pattern 2: position 3 = amount
                WHEN comma_count = 2 
                THEN ISNULL(TRY_CAST(MAX(CASE WHEN position = 3 THEN value END) AS DECIMAL(18,2)), 0)
                -- Pattern 0: try to extract amount from total_amount
                WHEN comma_count = 0 
                THEN ISNULL(TRY_CAST(total_amount AS DECIMAL(18,2)), 0)
                ELSE 0
            END
        ) AS amount
    FROM split_data
    GROUP BY 
        order_id,
        order_date,
        customer_id,
        delivery_address,
        payment_method,
        status,
        total_amount,
        comma_count,
        payment_method_numeric,
        status_numeric
)
-- ============================================================
-- 6. Insert into silver table with audit columns
-- ============================================================
INSERT INTO silver.ecommerce_orders (
    order_id,
    order_date,
    order_time,
    customer_id,
    delivery_address,
    delivery_fee,
    payment_method,
    order_status,
    amount,
    created_date,
    modified_date,
    data_load_date,
    source_system,
    etl_batch_id
)
SELECT 
    -- order_id
    ISNULL(order_id, 'Unknown') AS order_id,
    
    -- order_date - use TRY_CAST to handle invalid dates
    ISNULL(
        TRY_CAST(TRY_CAST(REPLACE(order_date, 'T', ' ') AS DATETIME) AS DATE),
        '1900-01-01'
    ) AS order_date,
    
    -- order_time - use TRY_CAST to handle invalid times
    ISNULL(
        TRY_CAST(TRY_CAST(REPLACE(order_date, 'T', ' ') AS DATETIME) AS TIME(0)),
        '00:00:00'
    ) AS order_time,
    
    -- customer_id - clean and handle NULLs
    CASE 
        WHEN customer_id IS NULL THEN 'Unknown'
        WHEN customer_id LIKE '%DUP' 
        THEN SUBSTRING(customer_id, 1, CHARINDEX('D', customer_id) - 2)
        ELSE customer_id
    END AS customer_id,
    
    -- delivery_address - clean and handle NULLs
    ISNULL(TRIM(REPLACE(delivery_address, '"', '')), 'Unknown') AS delivery_address,
    
    -- delivery_fee - already used ABS in final_data
    delivery_fee,
    
    -- payment_method - already cleaned
    payment_method,
    
    -- order_status - already cleaned
    order_status,
    
    -- amount - already used ABS in final_data
    amount,
    
    -- Audit columns
    GETDATE() AS created_date,
    GETDATE() AS modified_date,
    CAST(GETDATE() AS DATE) AS data_load_date,
    'bronze.ecommerce_orders_raw' AS source_system,
    @batch_id AS etl_batch_id
FROM final_data;
GO

-- ============================================================
-- 7. Update statistics
-- ============================================================
UPDATE STATISTICS silver.ecommerce_orders;
GO

-- ============================================================
-- 8. Create ETL Load Log Table (if it doesn't exist)
-- ============================================================
IF OBJECT_ID('silver.etl_load_log', 'U') IS NULL
BEGIN
    CREATE TABLE silver.etl_load_log (
        log_id INT IDENTITY(1,1) PRIMARY KEY,
        table_name VARCHAR(100) NOT NULL,
        rows_inserted INT NOT NULL,
        rows_updated INT NULL,
        rows_deleted INT NULL,
        load_date DATETIME2 NOT NULL DEFAULT GETDATE(),
        batch_id UNIQUEIDENTIFIER NOT NULL,
        status VARCHAR(20) NOT NULL,
        error_message VARCHAR(MAX) NULL
    );
END
GO

-- ============================================================
-- 9. Log the load
-- ============================================================
DECLARE @batch_id_log UNIQUEIDENTIFIER;
DECLARE @row_count INT;

-- Get the latest batch_id
SELECT TOP 1 @batch_id_log = etl_batch_id
FROM silver.ecommerce_orders
ORDER BY ecommerce_key DESC;

INSERT INTO silver.etl_load_log (
    table_name,
    rows_inserted,
    load_date,
    batch_id,
    status
)
SELECT 
    'silver.ecommerce_orders' AS table_name,
    COUNT(*) AS rows_inserted,
    GETDATE() AS load_date,
    @batch_id_log AS batch_id,
    'SUCCESS' AS status
FROM silver.ecommerce_orders
WHERE etl_batch_id = @batch_id_log;
GO

-- ============================================================
-- 10. Verification - Row Count Comparison
-- ============================================================

-- Get the latest batch_id for verification
DECLARE @verify_batch_id UNIQUEIDENTIFIER;
SELECT TOP 1 @verify_batch_id = etl_batch_id
FROM silver.ecommerce_orders
ORDER BY ecommerce_key DESC;

-- Compare source and target counts
SELECT 
    'Source Bronze' AS source,
    COUNT(*) AS row_count,
    '100.00%' AS percentage
FROM [Blue_canopy].[bronze].[ecommerce_orders_raw]

UNION ALL

SELECT 
    'Target Silver' AS source,
    COUNT(*) AS row_count,
    CAST(ROUND(
        (CAST(COUNT(*) AS FLOAT) / 
         (SELECT COUNT(*) FROM [Blue_canopy].[bronze].[ecommerce_orders_raw])) * 100, 
        2
    ) AS VARCHAR(20)) + '%' AS percentage
FROM silver.ecommerce_orders
WHERE etl_batch_id = @verify_batch_id

UNION ALL

SELECT 
    'Missing Rows' AS source,
    (SELECT COUNT(*) FROM [Blue_canopy].[bronze].[ecommerce_orders_raw]) -
    (SELECT COUNT(*) FROM silver.ecommerce_orders WHERE etl_batch_id = @verify_batch_id) AS row_count,
    CAST(ROUND(
        ((SELECT COUNT(*) FROM [Blue_canopy].[bronze].[ecommerce_orders_raw]) -
         (SELECT COUNT(*) FROM silver.ecommerce_orders WHERE etl_batch_id = @verify_batch_id)) * 100.0 /
         (SELECT COUNT(*) FROM [Blue_canopy].[bronze].[ecommerce_orders_raw]), 
        2
    ) AS VARCHAR(20)) + '%' AS percentage;
GO

-- ============================================================
-- 11. Data Quality Verification
-- ============================================================

DECLARE @quality_batch_id UNIQUEIDENTIFIER;
SELECT TOP 1 @quality_batch_id = etl_batch_id
FROM silver.ecommerce_orders
ORDER BY ecommerce_key DESC;

-- Check data quality metrics
SELECT 
    'Total Rows' AS metric,
    COUNT(*) AS value
FROM silver.ecommerce_orders
WHERE etl_batch_id = @quality_batch_id

UNION ALL

SELECT 
    'Unique Order IDs' AS metric,
    COUNT(DISTINCT order_id) AS value
FROM silver.ecommerce_orders
WHERE etl_batch_id = @quality_batch_id

UNION ALL

SELECT 
    'Unknown Customer IDs' AS metric,
    COUNT(*) AS value
FROM silver.ecommerce_orders
WHERE etl_batch_id = @quality_batch_id
AND customer_id = 'Unknown'

UNION ALL

SELECT 
    'Zero Amounts' AS metric,
    COUNT(*) AS value
FROM silver.ecommerce_orders
WHERE etl_batch_id = @quality_batch_id
AND amount = 0

UNION ALL

SELECT 
    'Negative Amounts' AS metric,
    COUNT(*) AS value
FROM silver.ecommerce_orders
WHERE etl_batch_id = @quality_batch_id
AND amount < 0

UNION ALL

SELECT 
    'Zero Delivery Fee' AS metric,
    COUNT(*) AS value
FROM silver.ecommerce_orders
WHERE etl_batch_id = @quality_batch_id
AND delivery_fee = 0;
GO

-- ============================================================
-- 12. Sample Data Preview
-- ============================================================
DECLARE @sample_batch_id UNIQUEIDENTIFIER;
SELECT TOP 1 @sample_batch_id = etl_batch_id
FROM silver.ecommerce_orders
ORDER BY ecommerce_key DESC;

SELECT TOP 20 
    ecommerce_key,
    order_id,
    order_date,
    order_time,
    customer_id,
    LEFT(delivery_address, 30) AS delivery_address_preview,
    delivery_fee,
    payment_method,
    order_status,
    amount,
    created_date
FROM silver.ecommerce_orders
WHERE etl_batch_id = @sample_batch_id
ORDER BY ecommerce_key;
GO

-- ============================================================
-- 13. Summary Statistics
-- ============================================================
DECLARE @stats_batch_id UNIQUEIDENTIFIER;
SELECT TOP 1 @stats_batch_id = etl_batch_id
FROM silver.ecommerce_orders
ORDER BY ecommerce_key DESC;

SELECT 
    COUNT(*) AS total_orders,
    COUNT(DISTINCT customer_id) AS unique_customers,
    MIN(order_date) AS first_order_date,
    MAX(order_date) AS last_order_date,
    SUM(amount) AS total_revenue,
    AVG(amount) AS average_order_value,
    SUM(delivery_fee) AS total_delivery_fees,
    AVG(delivery_fee) AS average_delivery_fee,
    MIN(amount) AS min_order_amount,
    MAX(amount) AS max_order_amount
FROM silver.ecommerce_orders
WHERE etl_batch_id = @stats_batch_id;
GO
