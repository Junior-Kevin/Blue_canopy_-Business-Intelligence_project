USE [Blue_canopy]
GO
/****** Object:  StoredProcedure [silver].[usp_LoadSilverLayer]    Script Date: 10/4/2026 5:11:29 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER   PROCEDURE [silver].[usp_LoadSilverLayer]
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @StartTime DATETIME2 = SYSDATETIME();

    -- ============================================================
    -- 1. silver.campaigns
    --    Marketing campaign headers with duration and budget variance.
    -- ============================================================
    PRINT 'Loading silver.campaigns...';
    DROP TABLE IF EXISTS silver.campaigns;

    ;WITH main AS (
        SELECT
            campaign_id,
            campaign_name,
            campaign_type,
            -- Default channel to 'Digital' if raw value is NULL
            CASE WHEN channel IS NULL THEN 'Digital' ELSE channel END AS channel,
            CAST(start_date AS DATE) AS start_date,
            CAST(end_date   AS DATE) AS end_date,
            CAST(budget_kes       AS DECIMAL(18,2)) AS budget_kes,
            CAST(actual_spend_kes AS DECIMAL(18,2)) AS actual_spend_kes,
            CAST(discount_rate    AS DECIMAL(9,4))  AS discount_rate
        FROM bronze.campaigns_raw
        -- Drop duplicate rows flagged with a '-DUP' suffix
        WHERE campaign_id NOT LIKE '%DUP'
    )
    SELECT
        CAST(campaign_id    AS NVARCHAR(50))  AS campaign_id,
        CAST(campaign_name  AS NVARCHAR(200)) AS campaign_name,
        CAST(campaign_type  AS NVARCHAR(50))  AS campaign_type,
        CAST(channel        AS NVARCHAR(50))  AS channel,
        start_date,
        end_date,
        -- Days between start and end
        DATEDIFF(DAY, start_date, end_date) AS campaign_duration_days,
        budget_kes,
        actual_spend_kes,
        -- Positive = under budget, negative = over budget
        budget_kes - actual_spend_kes AS variance,
        discount_rate
    INTO silver.campaigns
    FROM main;


    -- ============================================================
    -- 2. silver.competitor_quarterly
    --    Competitor revenue and market share by quarter.
    -- ============================================================
    PRINT 'Loading silver.competitor_quarterly...';
    DROP TABLE IF EXISTS silver.competitor_quarterly;

    SELECT
        ROW_NUMBER() OVER (ORDER BY [quarter], competitor_id, competitor_store_id) AS comp_qtr_key,
        CAST(competitor_id       AS NVARCHAR(50)) AS competitor_id,
        CAST(competitor_store_id AS NVARCHAR(50)) AS competitor_store_id,
        CAST([quarter]           AS NVARCHAR(20)) AS [quarter],
        TRY_CONVERT(BIGINT, revenue_kes)            AS revenue_kes,
        TRY_CONVERT(DECIMAL(9,4), market_share_pct) AS market_share_pct
    INTO silver.competitor_quarterly
    FROM bronze.competitor_quarterly_raw;


    -- ============================================================
    -- 3. silver.competitors
    --    Competitor master list.
    -- ============================================================
    PRINT 'Loading silver.competitors...';
    DROP TABLE IF EXISTS silver.competitors;

    SELECT
        CAST(competitor_id   AS NVARCHAR(50))  AS competitor_id,
        CAST(competitor_name AS NVARCHAR(200)) AS competitor_name
    INTO silver.competitors
    FROM bronze.competitors_raw;


    -- ============================================================
    -- 4. silver.competitor_stores
    --    Competitor store locations, deduplicated on store id.
    -- ============================================================
    PRINT 'Loading silver.competitor_stores...';
    DROP TABLE IF EXISTS silver.competitor_stores;

    ;WITH source_data AS (
        SELECT
            NULLIF(TRIM(competitor_store_id), '')  AS competitor_store_id,
            NULLIF(TRIM(competitor_id), '')        AS competitor_id,
            NULLIF(TRIM(location), '')             AS location,
            NULLIF(TRIM(county), '')               AS county,
            UPPER(NULLIF(TRIM(size_category), '')) AS size_category,
            -- Keep only the first row per competitor_store_id
            ROW_NUMBER() OVER (
                PARTITION BY NULLIF(TRIM(competitor_store_id), '')
                ORDER BY competitor_id, location, county
            ) AS row_num
        FROM bronze.competitor_stores_raw
    )
    SELECT
        CAST(competitor_store_id AS NVARCHAR(50))  AS competitor_store_id,
        CAST(competitor_id       AS NVARCHAR(50))  AS competitor_id,
        CAST(location            AS NVARCHAR(200)) AS location,
        CAST(county              AS NVARCHAR(100)) AS county,
        CAST(CASE size_category
            WHEN 'SMALL'  THEN 'Small'
            WHEN 'MEDIUM' THEN 'Medium'
            WHEN 'LARGE'  THEN 'Large'
            ELSE 'Unknown'
        END AS NVARCHAR(20)) AS size_category,
        CAST(CASE
            WHEN competitor_id IS NULL THEN 'Missing competitor ID'
            WHEN size_category NOT IN ('SMALL','MEDIUM','LARGE') OR size_category IS NULL
                THEN 'Invalid size category'
            ELSE 'Valid'
        END AS NVARCHAR(50)) AS quality_flag,
        SYSDATETIME() AS etl_load_date,
        CAST('bronze.competitor_stores_raw' AS NVARCHAR(100)) AS etl_source
    INTO silver.competitor_stores
    FROM source_data
    WHERE row_num = 1
      AND competitor_store_id IS NOT NULL;


    -- ============================================================
    -- 5. silver.crm
    --    Customer master with cleaned names, phones, dates,
    --    plus tenure, churn, and generation analytics.
    -- ============================================================
    PRINT 'Loading silver.crm...';
    DROP TABLE IF EXISTS silver.crm;

    -- Date span used for fabricating missing birth dates deterministically.
    -- Range: 1978-01-01 to 2010-12-31
    DECLARE @crm_start DATE = '1978-01-01';
    DECLARE @crm_end   DATE = '2010-12-31';
    DECLARE @crm_span  INT  = DATEDIFF(DAY, @crm_start, @crm_end) + 1;

    CREATE TABLE silver.crm (
        customer_id               NVARCHAR(50)  NOT NULL PRIMARY KEY,
        first_name                NVARCHAR(100) NULL,
        last_name                 NVARCHAR(100) NULL,
        full_name                 NVARCHAR(201) NULL,
        gender                    VARCHAR(20)   NULL,
        birth_date                DATE          NULL,
        age                       INT           NULL,
        age_band                  VARCHAR(20)   NULL,
        generation                VARCHAR(20)   NULL,   -- Gen Alpha / Gen Z / Millennial / Gen X / Boomer / Other
        phone                     VARCHAR(50)   NULL,
        email                     VARCHAR(255)  NULL,
        county                    VARCHAR(100)  NULL,
        town                      VARCHAR(100)  NULL,
        customer_segment          VARCHAR(50)   NULL,
        acquisition_channel       VARCHAR(50)   NULL,
        registration_date         DATE          NULL,
        churn_date                DATE          NULL,
        loyalty_tier              VARCHAR(50)   NULL,
        communication_preferences VARCHAR(100)  NULL,
        feedback_score            DECIMAL(5,2)  NULL,
        home_county               VARCHAR(100)  NULL,
        primary_store_id          NVARCHAR(50)  NULL,
        is_churned                BIT           NULL,
        tenure_days               INT           NULL,
        tenure_months             INT           NULL,
        tenure_band               VARCHAR(30)   NULL,
        registration_year         INT           NULL,
        registration_month        INT           NULL,
        registration_quarter      INT           NULL,
        email_domain              VARCHAR(100)  NULL,
        phone_prefix              VARCHAR(10)   NULL,
        is_phone_valid            BIT           NULL,
        is_email_valid            BIT           NULL,
        created_date              DATETIME2     CONSTRAINT DF_crm_created DEFAULT GETDATE(),
        updated_date              DATETIME2     CONSTRAINT DF_crm_updated DEFAULT GETDATE()
    );

    ;WITH deduplicated AS (
        -- Keep one row per customer, preferring rows with a churn_date,
        -- then the most recent registration.
        SELECT
            customer_id, first_name, last_name, birth_date, phone, email,
            county, town, customer_segment, acquisition_channel,
            registration_date, churn_date, loyalty_tier,
            communication_preferences, feedback_score,
            ROW_NUMBER() OVER (
                PARTITION BY customer_id
                ORDER BY CASE WHEN churn_date IS NULL THEN 1 ELSE 2 END,
                         registration_date DESC
            ) AS row_num
        FROM bronze.crm_raw
        WHERE customer_id NOT LIKE '%DUP%'
          AND customer_id IS NOT NULL
    ),
    cleaned AS (
        SELECT
            customer_id,
            -- Title-case first and last names
            TRIM(UPPER(LEFT(LOWER(first_name), 1)) + LOWER(SUBSTRING(first_name, 2, LEN(first_name)))) AS first_name,
            TRIM(UPPER(LEFT(LOWER(last_name), 1))  + LOWER(SUBSTRING(last_name, 2, LEN(last_name))))   AS last_name,
            -- Gender inferred from name length parity (source has no gender field)
            CASE WHEN (LEN(first_name) + LEN(last_name)) % 2 = 1 THEN 'Male' ELSE 'Female' END AS gender,
            birth_date        AS raw_birth_date,
            registration_date AS raw_registration_date,
            churn_date        AS raw_churn_date,
            -- Strip spaces, dashes, and leading +
            TRIM(REPLACE(REPLACE(REPLACE(phone, ' ', ''), '-', ''), '+', '')) AS phone,
            -- Replace placeholder 'example' domain with gmail
            TRIM(LOWER(REPLACE(email, 'example', 'gmail'))) AS email,
            TRIM(UPPER(LEFT(county, 1)) + LOWER(SUBSTRING(county, 2, LEN(county)))) AS county,
            TRIM(UPPER(LEFT(town, 1))   + LOWER(SUBSTRING(town, 2, LEN(town))))     AS town,
            CASE WHEN customer_segment IN ('Platinum','Gold','Silver','Bronze') THEN customer_segment ELSE 'Standard' END AS customer_segment,
            CASE WHEN acquisition_channel IN ('Online','Store','Referral','Social Media','Email') THEN acquisition_channel ELSE 'Other' END AS acquisition_channel,
            CASE WHEN loyalty_tier IN ('Platinum','Gold','Silver','Bronze') THEN loyalty_tier ELSE 'Bronze' END AS loyalty_tier,
            COALESCE(communication_preferences, 'Email') AS communication_preferences,
            TRY_CAST(feedback_score AS DECIMAL(5,2)) AS feedback_score,
            -- Deterministic offset from customer_id: same input -> same output
            ABS(CHECKSUM(customer_id)) % @crm_span AS random_days
        FROM deduplicated
        WHERE row_num = 1
    ),
    date_converted AS (
        SELECT
            *,
            -- Accept the date only if it is a valid non-sentinel value
            CASE
                WHEN ISDATE(raw_birth_date) = 1
                 AND raw_birth_date NOT LIKE '%[^0-9-]%'
                 AND raw_birth_date NOT IN ('2023-13-45', '1900-01-01')
                THEN CAST(raw_birth_date AS DATE)
                ELSE DATEADD(DAY, random_days, @crm_start)
            END AS clean_birth_date,
            CASE
                WHEN ISDATE(raw_registration_date) = 1
                 AND raw_registration_date NOT LIKE '%[^0-9-]%'
                 AND raw_registration_date NOT IN ('2023-13-45', '1900-01-01')
                THEN CAST(raw_registration_date AS DATE)
                ELSE DATEADD(DAY, random_days, @crm_start)
            END AS clean_registration_date,
            CASE
                WHEN raw_churn_date IS NULL THEN NULL
                WHEN ISDATE(raw_churn_date) = 1
                 AND raw_churn_date NOT LIKE '%[^0-9-]%'
                 AND raw_churn_date NOT IN ('2023-13-45', '1900-01-01')
                THEN CAST(raw_churn_date AS DATE)
                ELSE DATEADD(DAY, random_days, @crm_start)
            END AS clean_churn_date
        FROM cleaned
    ),
    customer_primary_store AS (
        -- For each customer, find the store they shopped at most,
        -- and that store's county as their home county.
        SELECT
            c.customer_id,
            p.store_id AS primary_store_id,
            s.county   AS home_county,
            ROW_NUMBER() OVER (
                PARTITION BY c.customer_id
                ORDER BY COUNT(*) DESC, p.store_id
            ) AS rn
        FROM date_converted c
        INNER JOIN bronze.pos_transactions_raw p ON c.customer_id = p.customer_id
        INNER JOIN bronze.stores_raw s           ON p.store_id    = s.store_id
        GROUP BY c.customer_id, p.store_id, s.county
    ),
    final_data AS (
        SELECT
            dc.customer_id, dc.first_name, dc.last_name,
            CONCAT(dc.first_name, ' ', dc.last_name) AS full_name,
            dc.gender,
            dc.clean_birth_date AS birth_date,
            DATEDIFF(YEAR, dc.clean_birth_date, GETDATE()) AS age,
            CASE
                WHEN dc.clean_birth_date IS NULL THEN 'Unknown'
                WHEN DATEDIFF(YEAR, dc.clean_birth_date, GETDATE()) < 18 THEN 'Under 18'
                WHEN DATEDIFF(YEAR, dc.clean_birth_date, GETDATE()) BETWEEN 18 AND 24 THEN '18-24'
                WHEN DATEDIFF(YEAR, dc.clean_birth_date, GETDATE()) BETWEEN 25 AND 34 THEN '25-34'
                WHEN DATEDIFF(YEAR, dc.clean_birth_date, GETDATE()) BETWEEN 35 AND 49 THEN '35-49'
                WHEN DATEDIFF(YEAR, dc.clean_birth_date, GETDATE()) BETWEEN 50 AND 64 THEN '50-64'
                ELSE '65+'
            END AS age_band,
            -- Generation derived from birth year
            CASE
                WHEN dc.clean_birth_date IS NULL THEN 'Unknown'
                WHEN YEAR(dc.clean_birth_date) BETWEEN 2013 AND YEAR(GETDATE()) THEN 'Gen Alpha'
                WHEN YEAR(dc.clean_birth_date) BETWEEN 1997 AND 2012 THEN 'Gen Z'
                WHEN YEAR(dc.clean_birth_date) BETWEEN 1981 AND 1996 THEN 'Millennial'
                WHEN YEAR(dc.clean_birth_date) BETWEEN 1965 AND 1980 THEN 'Gen X'
                WHEN YEAR(dc.clean_birth_date) BETWEEN 1945 AND 1964 THEN 'Boomer'
                ELSE 'Other/Unknown'
            END AS generation,
            -- Normalize Kenyan phone numbers to local format
            CASE
                WHEN LEN(dc.phone) = 9  AND dc.phone LIKE '7%'    THEN CONCAT('07', dc.phone)
                WHEN LEN(dc.phone) = 9  AND dc.phone LIKE '1%'    THEN CONCAT('01', dc.phone)
                WHEN LEN(dc.phone) = 10 AND dc.phone LIKE '07%'   THEN dc.phone
                WHEN LEN(dc.phone) = 12 AND dc.phone LIKE '2547%' THEN CONCAT('0', RIGHT(dc.phone, 9))
                ELSE dc.phone
            END AS phone,
            dc.email, dc.county, dc.town,
            dc.customer_segment, dc.acquisition_channel,
            dc.clean_registration_date AS registration_date,
            dc.clean_churn_date        AS churn_date,
            dc.loyalty_tier, dc.communication_preferences, dc.feedback_score,
            COALESCE(cps.home_county, 'Unknown') AS home_county,
            cps.primary_store_id,
            CASE WHEN dc.clean_churn_date IS NOT NULL AND dc.clean_churn_date <= GETDATE() THEN 1 ELSE 0 END AS is_churned,
            DATEDIFF(DAY,   dc.clean_registration_date, ISNULL(dc.clean_churn_date, GETDATE())) AS tenure_days,
            DATEDIFF(MONTH, dc.clean_registration_date, ISNULL(dc.clean_churn_date, GETDATE())) AS tenure_months,
            CASE
                WHEN DATEDIFF(DAY, dc.clean_registration_date, ISNULL(dc.clean_churn_date, GETDATE())) < 30  THEN 'New (<30 days)'
                WHEN DATEDIFF(DAY, dc.clean_registration_date, ISNULL(dc.clean_churn_date, GETDATE())) < 90  THEN 'Recent (30-90 days)'
                WHEN DATEDIFF(DAY, dc.clean_registration_date, ISNULL(dc.clean_churn_date, GETDATE())) < 180 THEN 'Regular (3-6 months)'
                WHEN DATEDIFF(DAY, dc.clean_registration_date, ISNULL(dc.clean_churn_date, GETDATE())) < 365 THEN 'Established (6-12 months)'
                ELSE 'Loyal (>1 year)'
            END AS tenure_band,
            YEAR(dc.clean_registration_date)              AS registration_year,
            MONTH(dc.clean_registration_date)             AS registration_month,
            DATEPART(QUARTER, dc.clean_registration_date) AS registration_quarter,
            CASE WHEN dc.email IS NOT NULL AND CHARINDEX('@', dc.email) > 0
                 THEN RIGHT(dc.email, LEN(dc.email) - CHARINDEX('@', dc.email)) END AS email_domain,
            LEFT(dc.phone, 3) AS phone_prefix,
            CASE WHEN LEN(dc.phone) BETWEEN 10 AND 12 AND dc.phone NOT LIKE '%[^0-9]%' THEN 1 ELSE 0 END AS is_phone_valid,
            CASE WHEN dc.email LIKE '%_@__%.__%' THEN 1 ELSE 0 END AS is_email_valid
        FROM date_converted dc
        LEFT JOIN customer_primary_store cps
               ON dc.customer_id = cps.customer_id AND cps.rn = 1
    )
    INSERT INTO silver.crm (
        customer_id, first_name, last_name, full_name, gender, birth_date, age, age_band,
        generation,
        phone, email, county, town, customer_segment, acquisition_channel,
        registration_date, churn_date, loyalty_tier, communication_preferences, feedback_score,
        home_county, primary_store_id, is_churned, tenure_days, tenure_months, tenure_band,
        registration_year, registration_month, registration_quarter, email_domain,
        phone_prefix, is_phone_valid, is_email_valid
    )
    SELECT
        customer_id, first_name, last_name, full_name, gender, birth_date, age, age_band,
        generation,
        phone, email, county, town, customer_segment, acquisition_channel,
        registration_date, churn_date, loyalty_tier, communication_preferences, feedback_score,
        home_county, primary_store_id, is_churned, tenure_days, tenure_months, tenure_band,
        registration_year, registration_month, registration_quarter, email_domain,
        phone_prefix, is_phone_valid, is_email_valid
    FROM final_data
    WHERE customer_id IS NOT NULL;


    -- ============================================================
    -- 6. silver.feedback
    --    Customer feedback with sentiment and quality flags.
    --    Only ratings 1-5 are kept.
    -- ============================================================
    PRINT 'Loading silver.feedback...';
    DROP TABLE IF EXISTS silver.feedback;

    ;WITH base AS (
        SELECT
            feedback_id, customer_id,
            CAST(date AS DATE) AS d,
            CAST(rating AS INT) AS rating,
            category
        FROM bronze.feedback_raw
        WHERE feedback_id IS NOT NULL
    ),
    cleaned AS (
        SELECT
            feedback_id,
            -- Strip '-DUP' suffix
            CASE WHEN customer_id LIKE '%-DUP%'
                 THEN LEFT(customer_id, CHARINDEX('-DUP', customer_id) - 1)
                 ELSE customer_id END AS customer_id_clean,
            d AS feedback_date,
            YEAR(d)  AS feedback_year,
            MONTH(d) AS feedback_month,
            DATEPART(QUARTER, d) AS feedback_quarter,
            FORMAT(d, 'yyyy-MM') AS feedback_year_month,
            rating,
            TRIM(category) AS category_clean,
            CASE WHEN rating >= 4 THEN 'Positive'
                 WHEN rating = 3  THEN 'Neutral'
                 WHEN rating <= 2 THEN 'Negative'
                 ELSE 'Unknown' END AS sentiment,
            CASE WHEN rating = 5 THEN 'Excellent'
                 WHEN rating = 4 THEN 'Good'
                 WHEN rating = 3 THEN 'Average'
                 WHEN rating = 2 THEN 'Poor'
                 WHEN rating = 1 THEN 'Very Poor'
                 ELSE 'Invalid' END AS rating_label,
            CASE WHEN rating < 1 OR rating > 5 THEN 'Invalid rating'
                 WHEN category IS NULL OR category = '' THEN 'Missing category'
                 WHEN d > GETDATE() THEN 'Future date'
                 WHEN d < '2015-01-01' THEN 'Suspicious old date'
                 ELSE 'Valid' END AS quality_flag
        FROM base
    )
    SELECT
        CAST(feedback_id AS NVARCHAR(50)) AS feedback_key,
        CAST(feedback_id AS NVARCHAR(50)) AS feedback_id,
        CAST(customer_id_clean AS NVARCHAR(50)) AS customer_id,
        feedback_date, feedback_year, feedback_month, feedback_quarter,
        CAST(feedback_year_month AS VARCHAR(7)) AS feedback_year_month,
        rating,
        CAST(rating_label AS VARCHAR(20)) AS rating_label,
        CAST(sentiment AS VARCHAR(20)) AS sentiment,
        CAST(category_clean AS NVARCHAR(100)) AS category,
        CASE WHEN feedback_date > GETDATE() THEN 1 ELSE 0 END AS is_future_dated,
        CAST(quality_flag AS VARCHAR(50)) AS quality_flag,
        GETDATE() AS etl_load_date,
        CAST('bronze.feedback_raw' AS NVARCHAR(100)) AS etl_source
    INTO silver.feedback
    FROM cleaned
    WHERE rating BETWEEN 1 AND 5;


    -- ============================================================
    -- 7. silver.ecommerce_order_lines
    --    E-commerce order lines with discount analytics.
    --    Duplicate product lines within an order are merged.
    -- ============================================================
    PRINT 'Loading silver.ecommerce_order_lines...';
    DROP TABLE IF EXISTS silver.ecommerce_order_lines;

    ;WITH base AS (
        SELECT
            order_id, line_number, product_id,
            CAST(quantity AS INT) AS quantity,
            ABS(TRY_CAST(unit_price AS DECIMAL(18,2)))   AS unit_price_kes,
            ABS(TRY_CAST(discount_rate AS DECIMAL(9,4))) AS discount_rate,
            ABS(TRY_CAST(line_total AS DECIMAL(18,2)))   AS line_total_kes
        FROM bronze.ecommerce_order_lines_raw
        WHERE order_id IS NOT NULL AND product_id IS NOT NULL
    ),
    validated AS (
        SELECT
            *,
            CAST(quantity * unit_price_kes * (1 - discount_rate) AS DECIMAL(18,2)) AS calculated_line_total,
            CAST(quantity * unit_price_kes * discount_rate       AS DECIMAL(18,2)) AS discount_amount_kes,
            CAST(unit_price_kes * (1 - discount_rate)            AS DECIMAL(18,2)) AS unit_price_after_discount_kes,
            LEFT(order_id, 4) AS order_prefix,
            TRY_CAST(RIGHT(order_id, 8) AS INT) AS order_sequence_number,
            CASE WHEN discount_rate = 0    THEN 'No Discount'
                 WHEN discount_rate < 0.05 THEN 'Small Discount (<5%)'
                 WHEN discount_rate < 0.10 THEN 'Standard Discount (5-10%)'
                 WHEN discount_rate < 0.20 THEN 'Large Discount (10-20%)'
                 ELSE 'Heavy Discount (>20%)' END AS discount_tier,
            CASE WHEN quantity <= 0 THEN 'Invalid quantity'
                 WHEN unit_price_kes <= 0 THEN 'Invalid unit price'
                 WHEN discount_rate < 0 OR discount_rate > 1 THEN 'Invalid discount rate'
                 WHEN line_total_kes <= 0 THEN 'Invalid line total'
                 ELSE 'Valid' END AS quality_flag
        FROM base
    ),
    aggregated AS (
        -- Same product appearing twice in one order gets merged
        SELECT
            order_id, product_id,
            ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY MIN(line_number)) AS line_number,
            SUM(quantity) AS quantity,
            AVG(unit_price_kes) AS unit_price_kes,
            AVG(discount_rate)  AS discount_rate,
            SUM(line_total_kes) AS line_total_kes,
            SUM(CAST(quantity * unit_price_kes * discount_rate AS DECIMAL(18,2))) AS discount_amount_kes,
            CAST(SUM(quantity * unit_price_kes * (1 - discount_rate)) / NULLIF(SUM(quantity), 0) AS DECIMAL(18,2)) AS unit_price_after_discount_kes,
            SUM(calculated_line_total) AS calculated_line_total,
            MAX(order_prefix) AS order_prefix,
            MAX(order_sequence_number) AS order_sequence_number,
            CASE WHEN COUNT(DISTINCT discount_tier) = 1 THEN MAX(discount_tier)
                 ELSE 'Mixed Discount Tiers' END AS discount_tier
        FROM validated
        WHERE quality_flag = 'Valid'
        GROUP BY order_id, product_id
    )
    SELECT
        ROW_NUMBER() OVER (ORDER BY order_id, line_number) AS order_line_key,
        CAST(order_id   AS NVARCHAR(50)) AS order_id,
        line_number,
        CAST(product_id AS NVARCHAR(50)) AS product_id,
        quantity, unit_price_kes, discount_rate,
        unit_price_after_discount_kes, discount_amount_kes, line_total_kes,
        calculated_line_total,
        CAST(discount_tier AS VARCHAR(30)) AS discount_tier,
        CAST(order_prefix  AS VARCHAR(10)) AS order_prefix,
        order_sequence_number,
        GETDATE() AS etl_load_date,
        CAST('bronze.ecommerce_order_lines_raw' AS NVARCHAR(100)) AS etl_source
    INTO silver.ecommerce_order_lines
    FROM aggregated;


    -- ============================================================
    -- 8. silver.ecommerce_orders
    --    E-commerce order headers.
    --    The raw source has messy total_amount values that hide
    --    delivery_fee, payment_method, and status; unpacked here
    --    with a comma-counting pattern.
    -- ============================================================
    PRINT 'Loading silver.ecommerce_orders...';
    DROP TABLE IF EXISTS silver.ecommerce_orders;

    CREATE TABLE silver.ecommerce_orders (
        ecommerce_key    INT IDENTITY(1,1) PRIMARY KEY CLUSTERED,
        order_id         VARCHAR(50)   NOT NULL,
        order_date       DATE          NOT NULL,
        order_time       TIME(0)       NOT NULL,
        customer_id      VARCHAR(50)   NOT NULL,
        delivery_address VARCHAR(500)  NOT NULL,
        delivery_fee     DECIMAL(18,2) NOT NULL DEFAULT 0,
        payment_method   VARCHAR(50)   NOT NULL,
        order_status     VARCHAR(50)   NULL,
        amount           DECIMAL(18,2) NOT NULL,
        created_date     DATETIME2     NOT NULL DEFAULT GETDATE(),
        modified_date    DATETIME2     NOT NULL DEFAULT GETDATE(),
        data_load_date   DATE          NOT NULL DEFAULT CAST(GETDATE() AS DATE),
        source_system    VARCHAR(50)   NOT NULL DEFAULT 'bronze.ecommerce_orders_raw',
        etl_batch_id     UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID()
    );

    ALTER TABLE silver.ecommerce_orders
    ADD CONSTRAINT CK_ecommerce_amount_positive CHECK (amount >= 0),
        CONSTRAINT CK_ecommerce_delivery_fee_positive CHECK (delivery_fee >= 0),
        CONSTRAINT CK_ecommerce_order_date_valid CHECK (order_date <= CAST(GETDATE() AS DATE));

    DECLARE @batch_id UNIQUEIDENTIFIER = NEWID();

    ;WITH pattern_analysis AS (
        SELECT
            order_id, order_date, customer_id, delivery_address,
            payment_method, status, total_amount,
            -- Count commas: tells us which pattern we're looking at
            LEN(total_amount) - LEN(REPLACE(total_amount, ',', '')) AS comma_count,
            TRY_CAST(payment_method AS INT) AS payment_method_numeric,
            TRY_CAST(status         AS INT) AS status_numeric
        FROM bronze.ecommerce_orders_raw
    ),
    split_data AS (
        SELECT p.*, value,
               ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY (SELECT NULL)) AS position
        FROM pattern_analysis p
        CROSS APPLY STRING_SPLIT(
            CASE WHEN p.total_amount IS NULL OR p.total_amount = ''
                 THEN 'NULL,NULL,NULL'
                 ELSE p.total_amount END,
            ','
        )
    ),
    final_data AS (
        SELECT
            order_id, order_date, customer_id, delivery_address, comma_count,
            payment_method_numeric, status_numeric,
            ABS(CASE
                WHEN comma_count = 1 AND payment_method_numeric IS NOT NULL THEN payment_method_numeric
                WHEN comma_count = 2 AND status_numeric IS NOT NULL THEN status_numeric
                WHEN comma_count = 0 AND payment_method_numeric IS NOT NULL THEN payment_method_numeric
                ELSE 0 END) AS delivery_fee,
            CASE
                WHEN comma_count = 1 THEN ISNULL(TRIM(status), 'Unknown')
                WHEN comma_count = 2 THEN ISNULL(TRIM(MAX(CASE WHEN position = 1 THEN value END)), 'Unknown')
                WHEN comma_count = 0 THEN ISNULL(TRIM(payment_method), 'Unknown')
                ELSE 'Unknown' END AS payment_method,
            CASE
                WHEN comma_count = 1 THEN TRIM(MAX(CASE WHEN position = 1 THEN value END))
                WHEN comma_count = 2 THEN TRIM(MAX(CASE WHEN position = 2 THEN value END))
                WHEN comma_count = 0 THEN TRIM(status) END AS order_status,
            ABS(CASE
                WHEN comma_count = 1 THEN ISNULL(TRY_CAST(MAX(CASE WHEN position = 2 THEN value END) AS DECIMAL(18,2)), 0)
                WHEN comma_count = 2 THEN ISNULL(TRY_CAST(MAX(CASE WHEN position = 3 THEN value END) AS DECIMAL(18,2)), 0)
                WHEN comma_count = 0 THEN ISNULL(TRY_CAST(total_amount AS DECIMAL(18,2)), 0)
                ELSE 0 END) AS amount
        FROM split_data
        GROUP BY order_id, order_date, customer_id, delivery_address,
                 payment_method, status, total_amount, comma_count,
                 payment_method_numeric, status_numeric
    )
    INSERT INTO silver.ecommerce_orders (
        order_id, order_date, order_time, customer_id, delivery_address,
        delivery_fee, payment_method, order_status, amount,
        created_date, modified_date, data_load_date, source_system, etl_batch_id
    )
    SELECT
        CAST(ISNULL(order_id, 'Unknown') AS VARCHAR(50)),
        ISNULL(TRY_CAST(TRY_CAST(REPLACE(order_date, 'T', ' ') AS DATETIME) AS DATE), '1900-01-01'),
        ISNULL(TRY_CAST(TRY_CAST(REPLACE(order_date, 'T', ' ') AS DATETIME) AS TIME(0)), '00:00:00'),
        CASE WHEN customer_id IS NULL THEN 'Unknown'
             WHEN customer_id LIKE '%DUP' THEN SUBSTRING(customer_id, 1, CHARINDEX('D', customer_id) - 2)
             ELSE customer_id END,
        CAST(ISNULL(TRIM(REPLACE(delivery_address, '"', '')), 'Unknown') AS VARCHAR(500)),
        delivery_fee,
        CAST(payment_method AS VARCHAR(50)),
        CAST(order_status   AS VARCHAR(50)),
        amount,
        GETDATE(), GETDATE(), CAST(GETDATE() AS DATE),
        'bronze.ecommerce_orders_raw', @batch_id
    FROM final_data;


    -- ============================================================
    -- 9. silver.ecomerce_returns
    --    Returns that came through the e-commerce channel
    --    (transaction ids not starting with TXN).
    -- ============================================================
    PRINT 'Loading silver.ecomerce_returns...';
    DROP TABLE IF EXISTS silver.ecomerce_returns;

    SELECT
        CAST(return_id AS NVARCHAR(50)) AS return_id,
        CAST(original_transaction_id AS NVARCHAR(50)) AS original_transaction_id,
        CAST(CASE WHEN return_date = '2023-13-45' THEN '2023-12-25' ELSE return_date END AS DATE) AS return_date,
        CAST(CASE WHEN product_id LIKE '%DUP' THEN LEFT(product_id, 9) ELSE product_id END AS NVARCHAR(50)) AS product_id,
        CAST(quantity_returned AS INT) AS quantity_returned,
        CAST(refund_amount AS DECIMAL(18,2)) AS refund_amount,
        CAST(return_reason AS NVARCHAR(200)) AS return_reason
    INTO silver.ecomerce_returns
    FROM bronze.returns_raw
    WHERE original_transaction_id NOT LIKE 'TXN%'
      AND return_id NOT LIKE '%DUP';


    -- ============================================================
    -- 10. silver.economic
    --     Macroeconomic indicators by county and month,
    --     plus a composite health score and outlier flags.
    -- ============================================================
    PRINT 'Loading silver.economic...';
    DROP TABLE IF EXISTS silver.economic;

    ;WITH base AS (
        SELECT
            county,
            DATEFROMPARTS(CAST(LEFT(year_month, 4) AS INT), CAST(RIGHT(year_month, 2) AS INT), 1) AS month_start_date,
            EOMONTH(DATEFROMPARTS(CAST(LEFT(year_month, 4) AS INT), CAST(RIGHT(year_month, 2) AS INT), 1)) AS [date],
            CAST(gdp_growth_pct      AS DECIMAL(9,4))  AS gdp_growth_pct,
            CAST(inflation_pct       AS DECIMAL(9,4))  AS inflation_pct,
            CAST(unemployment_pct    AS DECIMAL(9,4))  AS unemployment_pct,
            CAST(consumer_confidence AS DECIMAL(9,4))  AS consumer_confidence,
            CAST(retail_sales_index  AS DECIMAL(18,2)) AS retail_sales_index,
            CAST(fuel_price_kes      AS DECIMAL(18,2)) AS fuel_price_kes,
            CAST(usd_kes_rate        AS DECIMAL(18,4)) AS usd_kes_rate
        FROM bronze.economic_raw
    )
    SELECT
        CAST(CONCAT(county, '_', FORMAT([date], 'yyyyMM')) AS NVARCHAR(100)) AS economic_id,
        CAST(county AS NVARCHAR(100)) AS county,
        [date], month_start_date,
        YEAR([date])  AS calendar_year,
        MONTH([date]) AS calendar_month,
        DATEPART(QUARTER, [date]) AS calendar_quarter,
        CAST(CONCAT('Q', DATEPART(QUARTER, [date]), ' ', YEAR([date])) AS VARCHAR(10)) AS quarter_label,
        CAST(FORMAT([date], 'MMMM') AS VARCHAR(20)) AS month_name,
        gdp_growth_pct, inflation_pct, unemployment_pct, consumer_confidence,
        retail_sales_index, fuel_price_kes, usd_kes_rate,
        -- Inflation-adjusted retail sales index
        CAST(retail_sales_index * (100.0 / (100.0 + inflation_pct)) AS DECIMAL(18,2)) AS real_retail_sales_index,
        -- Weighted composite score (unemployment 40%, confidence 30%, GDP 30%)
        CAST((100 - unemployment_pct) * 0.4 + consumer_confidence * 0.3 + (50 + gdp_growth_pct * 5) * 0.3 AS DECIMAL(9,2)) AS economic_health_score,
        CAST(CASE
            WHEN gdp_growth_pct IS NULL THEN 'Missing GDP'
            WHEN inflation_pct < 0 OR inflation_pct > 50 THEN 'Invalid inflation'
            WHEN unemployment_pct < 0 OR unemployment_pct > 100 THEN 'Invalid unemployment'
            WHEN consumer_confidence < 0 OR consumer_confidence > 100 THEN 'Invalid confidence'
            WHEN retail_sales_index < 0 THEN 'Invalid retail index'
            WHEN fuel_price_kes <= 0 THEN 'Invalid fuel price'
            WHEN usd_kes_rate <= 0 THEN 'Invalid exchange rate'
            ELSE 'Valid' END AS VARCHAR(50)) AS quality_flag,
        CAST(CASE
            WHEN gdp_growth_pct > 10 THEN 'High Growth Alert'
            WHEN gdp_growth_pct < -5 THEN 'Recession Alert'
            WHEN inflation_pct > 20  THEN 'Hyperinflation Alert'
            WHEN usd_kes_rate > 200  THEN 'Currency Crisis Alert'
            ELSE 'Normal Range' END AS VARCHAR(50)) AS outlier_flag,
        GETDATE() AS etl_load_date,
        CAST('bronze.economic_raw' AS NVARCHAR(100)) AS etl_source
    INTO silver.economic
    FROM base
    WHERE [date] IS NOT NULL;


    -- ============================================================
    -- 11. silver.gift_card_transactions
    --     Gift card ledger. The first 'issue' per card is the
    --     original issuance; later 'issue' rows are top-ups.
    --     Redeems are stored as negative amounts.
    -- ============================================================
    PRINT 'Loading silver.gift_card_transactions...';
    DROP TABLE IF EXISTS silver.gift_card_transactions;

    ;WITH cards AS (
        SELECT
            -- Rank rows per card by date to identify the first 'issue'
            ROW_NUMBER() OVER (PARTITION BY card_number ORDER BY CAST([date] AS DATE)) AS flag,
            transaction_id, card_number,
            CAST([date] AS DATE) AS d,
            ABS(CAST(amount AS DECIMAL(18,2))) AS amount,
            LOWER(LTRIM(RTRIM([type]))) AS type,
            linked_transaction_id
        FROM bronze.gift_card_transactions_raw
    )
    SELECT
        CAST(transaction_id AS NVARCHAR(50)) AS transaction_id,
        CAST(card_number    AS NVARCHAR(50)) AS card_number,
        d AS [date],
        CAST(CASE
            WHEN (CASE WHEN flag = 1 AND type = 'issue' THEN 'issue'
                       WHEN flag != 1 AND type = 'issue' THEN 'top_up'
                       ELSE 'redeem' END) = 'redeem' THEN amount * -1
            ELSE amount END AS DECIMAL(18,2)) AS amount,
        CAST(CASE WHEN flag = 1 AND type = 'issue' THEN 'issue'
                  WHEN flag != 1 AND type = 'issue' THEN 'top_up'
                  ELSE 'redeem' END AS VARCHAR(20)) AS [type],
        CAST(linked_transaction_id AS NVARCHAR(50)) AS linked_transaction_id
    INTO silver.gift_card_transactions
    FROM cards;


    -- ============================================================
    -- 12. silver.gift_cards
    --     Gift card master. Reads straight from the bronze columns
    --     (bronze already split initial_balance / current_balance
    --     / transaction_ids during load).
    -- ============================================================
    PRINT 'Loading silver.gift_cards...';
    DROP TABLE IF EXISTS silver.gift_cards;

    SELECT
        CAST(card_number AS NVARCHAR(50)) AS card_number,
        CAST(customer_id AS NVARCHAR(50)) AS customer_id,
        CAST(issue_date  AS DATE) AS issue_date,
        CAST(expiry_date AS DATE) AS expiry_date,
        CAST(initial_balance AS DECIMAL(18,2)) AS initial_balance,
        CAST(current_balance AS DECIMAL(18,2)) AS current_balance,
        CAST(REPLACE(transaction_ids, '"', '') AS NVARCHAR(MAX)) AS transactions
    INTO silver.gift_cards
    FROM bronze.gift_cards_raw;


    -- ============================================================
    -- 13. silver.gis_counties
    --     County reference with population, income, and centroid.
    -- ============================================================
    PRINT 'Loading silver.gis_counties...';
    DROP TABLE IF EXISTS silver.gis_counties;

    SELECT
        ROW_NUMBER() OVER (ORDER BY county) AS county_key,
        CAST(county         AS NVARCHAR(100)) AS county,
        CAST(population     AS INT)           AS population,
        CAST(avg_income_kes AS DECIMAL(18,2)) AS avg_income_kes,
        CAST(latitude       AS DECIMAL(9,6))  AS latitude,
        CAST(longitude      AS DECIMAL(9,6))  AS longitude
    INTO silver.gis_counties
    FROM bronze.gis_counties_raw;


    -- ============================================================
    -- 14. silver.gl_transactions
    --     General ledger lines with account parsing, signed
    --     amounts, and account categorization by leading digit.
    -- ============================================================
    PRINT 'Loading silver.gl_transactions...';
    DROP TABLE IF EXISTS silver.gl_transactions;

    ;WITH base AS (
        SELECT
            transaction_id, account_code,
            CAST([date] AS DATE) AS transaction_date,
            CAST(amount AS DECIMAL(18,2)) AS amount,
            LOWER([type]) AS transaction_type,
            CASE WHEN store_id LIKE '%-DUP%'
                 THEN LEFT(store_id, CHARINDEX('-DUP', store_id) - 1)
                 ELSE store_id END AS store_id
        FROM bronze.gl_transactions_raw
        WHERE transaction_id IS NOT NULL
    ),
    cleaned AS (
        SELECT
            transaction_id, account_code,
            -- Account code format is "NNNN-Account Name"
            LEFT(account_code, CHARINDEX('-', account_code) - 1) AS account_number,
            RIGHT(account_code, LEN(account_code) - CHARINDEX('-', account_code)) AS account_name,
            store_id, transaction_date,
            YEAR(transaction_date)  AS transaction_year,
            MONTH(transaction_date) AS transaction_month,
            DATEPART(QUARTER, transaction_date) AS transaction_quarter,
            FORMAT(transaction_date, 'yyyy-MM') AS transaction_year_month,
            amount, transaction_type,
            -- Two signed views: from debit and credit perspectives
            CASE WHEN transaction_type = 'debit'  THEN amount
                 WHEN transaction_type = 'credit' THEN -amount ELSE 0 END AS signed_amount_debit_view,
            CASE WHEN transaction_type = 'credit' THEN amount
                 WHEN transaction_type = 'debit'  THEN -amount ELSE 0 END AS signed_amount_credit_view,
            -- Account category inferred from first digit of account code
            CASE
                WHEN LEFT(account_code, 1) = '1' THEN 'Assets'
                WHEN LEFT(account_code, 1) = '2' THEN 'Liabilities'
                WHEN LEFT(account_code, 1) = '3' THEN 'Equity'
                WHEN LEFT(account_code, 1) = '4' THEN 'Revenue'
                WHEN LEFT(account_code, 1) = '5' THEN 'Cost of Goods Sold'
                WHEN LEFT(account_code, 1) = '6' THEN 'Operating Expenses'
                WHEN LEFT(account_code, 1) = '7' THEN 'Other Income/Expense'
                ELSE 'Other' END AS account_category,
            CASE
                WHEN amount <= 0 THEN 'Invalid amount'
                WHEN transaction_type NOT IN ('debit', 'credit') THEN 'Invalid transaction type'
                WHEN store_id IS NULL THEN 'Missing store'
                WHEN account_code IS NULL THEN 'Missing account'
                ELSE 'Valid' END AS quality_flag
        FROM base
    )
    SELECT
        CAST(transaction_id AS NVARCHAR(50)) AS gl_transaction_key,
        CAST(transaction_id AS NVARCHAR(50)) AS transaction_id,
        CAST(account_code   AS NVARCHAR(50)) AS account_code,
        CAST(account_number AS NVARCHAR(20)) AS account_number,
        CAST(account_name   AS NVARCHAR(100)) AS account_name,
        CAST(account_category AS VARCHAR(50)) AS account_category,
        CAST(store_id       AS NVARCHAR(50)) AS store_id,
        transaction_date,
        CAST(transaction_type AS VARCHAR(20)) AS transaction_type,
        amount, signed_amount_debit_view, signed_amount_credit_view,
        transaction_year, transaction_month, transaction_quarter,
        CAST(transaction_year_month AS VARCHAR(7)) AS transaction_year_month,
        CAST(quality_flag AS VARCHAR(50)) AS quality_flag,
        GETDATE() AS etl_load_date,
        CAST('bronze.gl_transactions_raw' AS NVARCHAR(100)) AS etl_source
    INTO silver.gl_transactions
    FROM cleaned
    WHERE quality_flag = 'Valid';


    -- ============================================================
    -- 15. silver.goods_receipts
    --     Goods receipt notes with quality categorization.
    -- ============================================================
    PRINT 'Loading silver.goods_receipts...';
    DROP TABLE IF EXISTS silver.goods_receipts;

    ;WITH base AS (
        SELECT
            receipt_id, po_number,
            CAST(CASE WHEN receipt_date = '2023-13-45' THEN '2023-12-25' ELSE receipt_date END AS DATE) AS receipt_date,
            product_id,
            CAST(quantity_received AS INT) AS quantity_received,
            receiving_notes
        FROM bronze.goods_receipts_raw
        WHERE receipt_id IS NOT NULL AND po_number IS NOT NULL
    ),
    cleaned AS (
        SELECT
            receipt_id, product_id,
            UPPER(TRIM(po_number)) AS po_number_clean,
            receipt_date,
            YEAR(receipt_date)  AS receipt_year,
            MONTH(receipt_date) AS receipt_month,
            DATEPART(QUARTER, receipt_date) AS receipt_quarter,
            FORMAT(receipt_date, 'yyyy-MM') AS receipt_year_month,
            quantity_received,
            -- Replace literal 'NULL' string with an actual description
            COALESCE(CASE WHEN receiving_notes = 'NULL' THEN NULL ELSE receiving_notes END,
                     'No issues recorded') AS receiving_notes_clean,
            CASE
                WHEN receiving_notes LIKE '%Damaged%' THEN 'Damaged Goods'
                WHEN receiving_notes LIKE '%Wrong%'   THEN 'Wrong Items'
                WHEN receiving_notes LIKE '%OK%'      THEN 'Good Condition'
                WHEN receiving_notes IS NULL OR receiving_notes = 'NULL' THEN 'No Issues Recorded'
                ELSE 'Other Issue' END AS receipt_quality_category,
            CASE WHEN receiving_notes IN ('Damaged in transit', 'Wrong items', 'Shortage') THEN 1 ELSE 0 END AS has_quality_issue,
            CASE
                WHEN quantity_received <= 0 THEN 'Invalid quantity'
                WHEN receipt_date > GETDATE() THEN 'Future receipt date'
                WHEN receipt_date < '2015-01-01' THEN 'Suspicious old date'
                WHEN product_id IS NULL THEN 'Missing product'
                ELSE 'Valid' END AS quality_flag
        FROM base
    )
    SELECT
        CAST(receipt_id AS NVARCHAR(50)) AS receipt_key,
        CAST(receipt_id AS NVARCHAR(50)) AS receipt_id,
        CAST(po_number_clean AS NVARCHAR(50)) AS po_number,
        CAST(product_id AS NVARCHAR(50)) AS product_id,
        receipt_date, quantity_received,
        CAST(receiving_notes_clean AS NVARCHAR(500)) AS receiving_notes,
        CAST(receipt_quality_category AS VARCHAR(50)) AS receipt_quality_category,
        CAST(has_quality_issue AS BIT) AS has_quality_issue,
        receipt_year, receipt_month, receipt_quarter,
        CAST(receipt_year_month AS VARCHAR(7)) AS receipt_year_month,
        CAST(quality_flag AS VARCHAR(50)) AS quality_flag,
        GETDATE() AS etl_load_date,
        CAST('bronze.goods_receipts_raw' AS NVARCHAR(100)) AS etl_source
    INTO silver.goods_receipts
    FROM cleaned
    WHERE quantity_received > 0;


    -- ============================================================
    -- 16. silver.hr
    --     Employee records with tenure, salary bands, education
    --     (inferred from job title), and organizational groupings.
    -- ============================================================
    PRINT 'Loading silver.hr...';
    DROP TABLE IF EXISTS silver.hr;

    ;WITH DateCleaned AS (
        SELECT
            employee_id, first_name, last_name, gender, department, job_title,
            salary,
			CASE
	           WHEN store_id IS NULL THEN 'HQ' ELSE
		       SUBSTRING(store_id,1,9) 
	        END store_id, shift_pattern,
            -- Convert date strings safely; sentinel value -> NULL
            TRY_CAST(CASE WHEN valid_from = '2023-13-45' OR valid_from LIKE '%[^0-9-]%' THEN NULL ELSE valid_from END AS DATE) AS valid_from,
            TRY_CAST(CASE WHEN valid_to   = '2023-13-45' OR valid_to   LIKE '%[^0-9-]%' THEN NULL ELSE valid_to   END AS DATE) AS valid_to,
            TRY_CAST(CASE WHEN birth_date = '2023-13-45' OR birth_date LIKE '%[^0-9-]%' THEN NULL ELSE birth_date END AS DATE) AS birth_date,
            TRY_CAST(CASE WHEN hire_date  = '2023-13-45' OR hire_date  LIKE '%[^0-9-]%' THEN NULL ELSE hire_date  END AS DATE) AS hire_date,
            TRY_CAST(salary AS INT) AS salary_clean
        FROM bronze.hr_raw
        WHERE employee_id NOT LIKE '%DUP'
    ),
    EducationData AS (
        SELECT
            *,
            -- Education is not in the source; inferred deterministically
            -- from the employee_id so re-runs are reproducible.
            CASE
                WHEN job_title IN ('Store Manager','Finance Manager','Warehouse Manager','Supply Chain Manager','IT Manager','HR Manager')
                    THEN CASE ABS(CHECKSUM(employee_id)) % 3
                            WHEN 0 THEN 'Bachelor''s Degree' WHEN 1 THEN 'Master''s Degree' ELSE 'MBA' END
                WHEN job_title IN ('Marketing Manager','Brand Officer','Recruiter','Accountant','Senior Sales',
                                   'Procurement Officer','Logistics Officer','Customer Care','Digital Officer',
                                   'Auditor','Systems Admin','HR Officer')
                    THEN 'Bachelor''s Degree'
                WHEN job_title IN ('Supervisor','Assistant Manager')
                    THEN CASE ABS(CHECKSUM(employee_id)) % 3
                            WHEN 0 THEN 'Bachelor''s Degree' WHEN 1 THEN 'Master''s Degree' ELSE 'Associate Degree' END
                WHEN job_title IN ('Cashier','Sales Associate','Stock Keeper','Loader','Forklift Operator',
                                   'Security','Support','Promoter')
                    THEN CASE ABS(CHECKSUM(employee_id)) % 3
                            WHEN 0 THEN 'High School Diploma' WHEN 1 THEN 'Some College' ELSE 'Associate Degree' END
                WHEN job_title IS NULL
                    THEN CASE ABS(CHECKSUM(employee_id)) % 5
                            WHEN 0 THEN 'High School Diploma' WHEN 1 THEN 'Some College'
                            WHEN 2 THEN 'Associate Degree' WHEN 3 THEN 'Bachelor''s Degree'
                            ELSE 'Master''s Degree' END
                ELSE CASE ABS(CHECKSUM(employee_id)) % 4
                        WHEN 0 THEN 'High School Diploma' WHEN 1 THEN 'Some College'
                        WHEN 2 THEN 'Associate Degree' ELSE 'Bachelor''s Degree' END
            END AS education_level
        FROM DateCleaned
    )
    SELECT
        CAST(employee_id AS NVARCHAR(50)) AS employee_id,
        CAST(first_name  AS NVARCHAR(100)) AS first_name,
        CAST(last_name   AS NVARCHAR(100)) AS last_name,
        CAST(gender      AS VARCHAR(20)) AS gender,
        CAST(department  AS NVARCHAR(100)) AS department,
        -- Fill in a job title based on department when missing
        CAST(CASE
            WHEN job_title IS NULL AND department = 'Finance'          THEN 'Finance Analyst'
            WHEN job_title IS NULL AND department = 'HR'               THEN 'HR Officer'
            WHEN job_title IS NULL AND department = 'IT'               THEN 'Support'
            WHEN job_title IS NULL AND department = 'Marketing'        THEN 'Brand Officer'
            WHEN job_title IS NULL AND department = 'Sales'            THEN 'Promoter'
            WHEN job_title IS NULL AND department = 'Store Operations' THEN 'Cashier'
            WHEN job_title IS NULL AND department = 'Supply Chain'     THEN 'Procurement Officer'
            WHEN job_title IS NULL AND department = 'Warehouse'        THEN 'Stock Keeper'
            ELSE job_title END AS NVARCHAR(100)) AS job_title,
        CAST(store_id      AS NVARCHAR(50)) AS store_id,
        CAST(shift_pattern AS NVARCHAR(50)) AS shift_pattern,
        -- valid_from is backfilled from the previous row's valid_to + 1
        CAST(COALESCE(CAST(DATEADD(DAY, 1, LAG(valid_to) OVER (PARTITION BY employee_id ORDER BY valid_from, valid_to)) AS DATE), valid_from) AS DATE) AS valid_from,
        CAST(CASE WHEN valid_to IS NULL THEN GETDATE() ELSE valid_to END AS DATE) AS valid_to,
        birth_date, hire_date,
        COALESCE(salary_clean, 0) AS salary,
        CAST(education_level AS VARCHAR(50)) AS education_level,
        CASE WHEN birth_date IS NOT NULL THEN DATEDIFF(YEAR, birth_date, GETDATE()) END AS age,
        CASE
            WHEN birth_date IS NULL THEN 'Unknown'
            WHEN DATEDIFF(YEAR, birth_date, GETDATE()) < 25 THEN 'Gen Z (18-24)'
            WHEN DATEDIFF(YEAR, birth_date, GETDATE()) < 35 THEN 'Young Millennial (25-34)'
            WHEN DATEDIFF(YEAR, birth_date, GETDATE()) < 45 THEN 'Senior Millennial (35-44)'
            WHEN DATEDIFF(YEAR, birth_date, GETDATE()) < 55 THEN 'Gen X (45-54)'
            ELSE 'Boomer+ (55+)' END AS generation,
        CONCAT(COALESCE(first_name, ''), ' ', COALESCE(last_name, '')) AS full_name,
        LEFT(COALESCE(first_name, 'N'), 1) + '. ' + COALESCE(last_name, 'Unknown') AS display_name,
        LOWER(CONCAT(COALESCE(first_name, 'unknown'), '.', COALESCE(last_name, 'unknown'), '@company.com')) AS generated_email,
        CASE WHEN hire_date IS NOT NULL THEN DATEDIFF(DAY,   hire_date, GETDATE()) END AS tenure_days,
        CASE WHEN hire_date IS NOT NULL THEN DATEDIFF(MONTH, hire_date, GETDATE()) END AS tenure_months,
        CASE WHEN hire_date IS NOT NULL THEN DATEDIFF(YEAR,  hire_date, GETDATE()) END AS tenure_years,
        CASE
            WHEN hire_date IS NULL THEN 'Unknown'
            WHEN DATEDIFF(YEAR, hire_date, GETDATE()) < 1  THEN 'Probation (<1 year)'
            WHEN DATEDIFF(YEAR, hire_date, GETDATE()) < 3  THEN 'Junior (1-3 years)'
            WHEN DATEDIFF(YEAR, hire_date, GETDATE()) < 5  THEN 'Mid (3-5 years)'
            WHEN DATEDIFF(YEAR, hire_date, GETDATE()) < 10 THEN 'Senior (5-10 years)'
            ELSE 'Veteran (10+ years)' END AS tenure_band,
        CASE
            WHEN hire_date IS NULL THEN 'Unknown'
            WHEN DATEDIFF(YEAR, hire_date, GETDATE()) BETWEEN 1 AND 2 THEN 'High Risk'
            WHEN DATEDIFF(YEAR, hire_date, GETDATE()) > 10 THEN 'Low Risk'
            ELSE 'Medium Risk' END AS retention_risk,
        CASE
            WHEN valid_to IS NULL THEN 'Active'
            WHEN valid_to > GETDATE() THEN 'Active'
            ELSE 'Inactive/Terminated' END AS employment_status,
        CASE WHEN valid_from IS NULL THEN NULL ELSE DATEDIFF(MONTH, valid_from, COALESCE(valid_to, GETDATE())) END AS contract_length_months,
        CASE
            WHEN valid_from IS NULL THEN 'Unknown'
            WHEN DATEDIFF(MONTH, valid_from, COALESCE(valid_to, GETDATE())) <= 12 THEN 'Short-term Contract'
            WHEN DATEDIFF(MONTH, valid_from, COALESCE(valid_to, GETDATE())) <= 24 THEN 'Medium-term Contract'
            WHEN valid_to IS NULL THEN 'Permanent'
            ELSE 'Long-term Contract' END AS contract_type,
        CASE
            WHEN salary_clean < 30000  THEN 'Entry Level (<30K)'
            WHEN salary_clean < 45000  THEN 'Junior (30-45K)'
            WHEN salary_clean < 60000  THEN 'Mid (45-60K)'
            WHEN salary_clean < 80000  THEN 'Senior (60-80K)'
            WHEN salary_clean < 100000 THEN 'Lead (80-100K)'
            ELSE 'Executive (100K+)' END AS salary_band,
        CASE
            WHEN hire_date IS NULL OR salary_clean IS NULL THEN 'Unknown'
            WHEN salary_clean < 30000 AND DATEDIFF(YEAR, hire_date, GETDATE()) > 5 THEN 'Underpaid'
            WHEN salary_clean > 80000 AND DATEDIFF(YEAR, hire_date, GETDATE()) < 2 THEN 'Overpaid'
            ELSE 'Market Rate' END AS salary_equity_flag,
        CASE
            WHEN department IN ('Sales','Marketing','Brand') THEN 'Revenue'
            WHEN department IN ('HR','Finance','IT','Legal') THEN 'Corporate'
            WHEN department IN ('Warehouse','Logistics','Operations') THEN 'Operations'
            WHEN department IN ('Customer Care','Support') THEN 'Customer Service'
            ELSE COALESCE(department, 'Other') END AS department_category,
        CASE
            WHEN job_title LIKE '%Manager%' OR job_title LIKE '%Director%' THEN 'Management'
            WHEN job_title LIKE '%Senior%' OR job_title LIKE '%Lead%' THEN 'Senior'
            WHEN job_title LIKE '%Assistant%' OR job_title LIKE '%Junior%' THEN 'Junior'
            WHEN job_title LIKE '%Intern%' THEN 'Intern'
            ELSE COALESCE(job_title, 'Staff') END AS job_level,
        CAST(CASE WHEN job_title LIKE '%Manager%' OR job_title LIKE '%Director%'
                    OR job_title LIKE '%Supervisor%' OR job_title LIKE '%Lead%'
                  THEN 1 ELSE 0 END AS BIT) AS is_manager,
        CASE WHEN hire_date IS NOT NULL THEN DATEPART(MONTH,   hire_date) END AS hire_month,
        CASE WHEN hire_date IS NOT NULL THEN DATEPART(QUARTER, hire_date) END AS hire_quarter,
        CASE
            WHEN hire_date IS NULL THEN 'Unknown'
            WHEN DATEPART(MONTH, hire_date) IN (12,1,2) THEN 'Winter'
            WHEN DATEPART(MONTH, hire_date) IN (3,4,5)  THEN 'Spring'
            WHEN DATEPART(MONTH, hire_date) IN (6,7,8)  THEN 'Summer'
            ELSE 'Fall' END AS hire_season,
        CASE WHEN hire_date IS NOT NULL THEN YEAR(hire_date) END AS hire_year,
        CASE WHEN hire_date IS NOT NULL THEN YEAR(GETDATE()) - YEAR(hire_date) END AS years_since_hire,
        CASE
            WHEN hire_date IS NULL THEN 'Unknown'
            ELSE CONCAT(YEAR(hire_date), '-',
                CASE WHEN DATEPART(MONTH, hire_date) <= 3 THEN 'Q1'
                     WHEN DATEPART(MONTH, hire_date) <= 6 THEN 'Q2'
                     WHEN DATEPART(MONTH, hire_date) <= 9 THEN 'Q3'
                     ELSE 'Q4' END) END AS hire_cohort,
        CASE
            WHEN gender IN ('Male','M') THEN 'Male'
            WHEN gender IN ('Female','F') THEN 'Female'
            ELSE 'Other/Not Specified' END AS gender_category,
        CASE
            WHEN birth_date IS NULL THEN 'Unknown'
            WHEN DATEDIFF(YEAR, birth_date, GETDATE()) < 30 THEN 'Under 30'
            WHEN DATEDIFF(YEAR, birth_date, GETDATE()) < 40 THEN '30-39'
            WHEN DATEDIFF(YEAR, birth_date, GETDATE()) < 50 THEN '40-49'
            ELSE '50+' END AS age_band
    INTO silver.hr
    FROM EducationData;


    -- ============================================================
    -- 17. silver.service_interactions
    --     Customer service contacts with rating labels.
    -- ============================================================
    PRINT 'Loading silver.service_interactions...';
    DROP TABLE IF EXISTS silver.service_interactions;

    SELECT
        CAST(interaction_id AS NVARCHAR(50)) AS interaction_id,
        CAST(LEFT(customer_id, 11) AS NVARCHAR(50)) AS customer_id,
        CAST(CASE WHEN interaction_date = '2023-13-45' THEN '2023-12-25' ELSE interaction_date END AS DATE) AS interaction_date,
        CAST(channel AS NVARCHAR(50)) AS channel,
        CAST(CASE
            WHEN ABS(CAST(satisfaction_score AS DECIMAL(9,4))) = 1 THEN 'very poor'
            WHEN ABS(CAST(satisfaction_score AS DECIMAL(9,4))) = 2 THEN 'poor'
            WHEN ABS(CAST(satisfaction_score AS DECIMAL(9,4))) = 3 THEN 'average'
            WHEN ABS(CAST(satisfaction_score AS DECIMAL(9,4))) = 4 THEN 'good'
            WHEN ABS(CAST(satisfaction_score AS DECIMAL(9,4))) = 5 THEN 'excellent'
            ELSE 'neutral' END AS VARCHAR(20)) AS rating_label,
        CAST(issue_type AS NVARCHAR(100)) AS issue_type,
        ABS(CAST(resolution_time_minutes AS INT)) AS resolution_time_minutes,
        ABS(CAST(satisfaction_score AS DECIMAL(9,4))) AS satisfaction_score
    INTO silver.service_interactions
    FROM bronze.service_interactions_raw;


    -- ============================================================
    -- 18. silver.inventory_movements
    --     Stock movements with running quantities per
    --     product-store and per product.
    -- ============================================================
    PRINT 'Loading silver.inventory_movements...';
    DROP TABLE IF EXISTS silver.inventory_movements;

    ;WITH base AS (
        SELECT
            movement_id,
            CAST(CASE WHEN movement_date = '2023-13-45' THEN '2022-10-15' ELSE movement_date END AS DATE) AS movement_date,
            store_id, product_id, movement_type,
            CAST(quantity      AS DECIMAL(18,4)) AS quantity,
            CAST(unit_cost_kes AS DECIMAL(18,2)) AS unit_cost_kes
        FROM bronze.inventory_movements_raw
        WHERE movement_date IS NOT NULL
          AND movement_id NOT LIKE '%DUP'
    ),
    cleaned AS (
        SELECT
            movement_id,
            movement_date,
            -- Strip '-DUP' suffix from store_id
            CASE WHEN store_id LIKE '%-DUP%'
                 THEN LEFT(store_id, CHARINDEX('-DUP', store_id) - 1)
                 ELSE store_id END AS store_id_clean,
            -- Strip '-DUP' suffix from product_id
            CASE WHEN product_id LIKE '%-DUP'
                 THEN REPLACE(product_id, '-DUP', '')
                 ELSE product_id END AS product_id_clean,
            movement_type,
            ABS(quantity) AS quantity_absolute,
            quantity AS quantity_raw,
            -- Signed quantity: outbound movements are negative, inbound positive.
            -- ADJUSTMENT preserves the source sign (can be either direction).
            CASE
                WHEN movement_type IN ('SALE','TRANSFER_OUT','ADJUSTMENT_OUT','DAMAGE','LOSS')
                    THEN -ABS(quantity)
                WHEN movement_type = 'ADJUSTMENT'
                    THEN quantity
                ELSE ABS(quantity)
            END AS quantity_signed,
            unit_cost_kes,
            CAST(ABS(quantity) * unit_cost_kes AS DECIMAL(18,2)) AS movement_value_kes,
            YEAR(movement_date)              AS movement_year,
            MONTH(movement_date)             AS movement_month,
            DATEPART(QUARTER, movement_date) AS movement_quarter,
            FORMAT(movement_date, 'yyyy-MM') AS movement_year_month,
            FORMAT(movement_date, 'MMMM')    AS movement_month_name,
            CASE
                WHEN movement_type IN ('SALE','TRANSFER_OUT','ADJUSTMENT_OUT','DAMAGE','LOSS')
                     AND quantity > 0
                    THEN 'Positive quantity for outbound'
                WHEN movement_type IN ('RECEIPT','TRANSFER_IN','ADJUSTMENT_IN','RETURN')
                     AND quantity < 0
                    THEN 'Negative quantity for inbound'
                ELSE 'Valid sign'
            END AS sign_validation_flag
        FROM base
    ),
    with_running AS (
        SELECT
            *,
            -- Stock level per product-store at each movement.
            -- Partitioned by cleaned product_id so '-DUP' variants share a ledger.
            SUM(quantity_signed) OVER (
                PARTITION BY product_id_clean, store_id_clean
                ORDER BY movement_date, movement_id
                ROWS UNBOUNDED PRECEDING
            ) AS running_quantity,

            -- Cumulative flow per product across all stores
            SUM(quantity_signed) OVER (
                PARTITION BY product_id_clean
                ORDER BY movement_date, movement_id
                ROWS UNBOUNDED PRECEDING
            ) AS cumulative_sum_by_product,

            -- Rolling 3-movement demand velocity, per store.
            -- Sums signed quantities over the current and previous 2 movements.
            SUM(quantity_signed) OVER (
                PARTITION BY product_id_clean, store_id_clean
                ORDER BY movement_date, movement_id
                ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
            ) AS moving_sum_3_transactions
        FROM cleaned
    )
    SELECT
        CAST(CONCAT(movement_id, '_', FORMAT(movement_date, 'yyyyMMdd')) AS NVARCHAR(100)) AS inventory_movement_key,
        CAST(movement_id AS NVARCHAR(50)) AS movement_id,
        movement_date,
        CAST(store_id_clean   AS NVARCHAR(50)) AS store_id,
        CAST(product_id_clean AS NVARCHAR(50)) AS product_id,
        CAST(movement_type    AS NVARCHAR(50)) AS movement_type,
        CAST(quantity_signed   AS DECIMAL(18,2)) AS quantity,
        CAST(quantity_absolute AS DECIMAL(18,2)) AS quantity_absolute,
        unit_cost_kes,
        movement_value_kes,
        CAST(running_quantity            AS DECIMAL(18,2)) AS running_quantity,
        CAST(cumulative_sum_by_product   AS DECIMAL(18,2)) AS cumulative_sum_by_product,
        CAST(moving_sum_3_transactions   AS DECIMAL(18,2)) AS moving_sum_3_transactions,
        CAST(CASE
            WHEN running_quantity < 0                    THEN 'Negative stock alert'
            WHEN running_quantity = 0                    THEN 'Zero stock'
            WHEN running_quantity BETWEEN 1 AND 50       THEN 'Low stock'
            WHEN running_quantity BETWEEN 51 AND 200     THEN 'Adequate stock'
            WHEN running_quantity > 200                  THEN 'Excess stock'
            ELSE 'Unknown'
        END AS VARCHAR(30)) AS inventory_status,
        CAST(CASE
            WHEN moving_sum_3_transactions > 100         THEN 'High demand - Reorder now'
            WHEN moving_sum_3_transactions BETWEEN 30 AND 100 THEN 'Normal demand'
            WHEN moving_sum_3_transactions BETWEEN 1 AND 29   THEN 'Low demand - Reduce stock'
            WHEN moving_sum_3_transactions = 0           THEN 'No recent activity'
            ELSE 'Insufficient data'
        END AS VARCHAR(30)) AS demand_velocity,
        movement_year, movement_month, movement_quarter,
        CAST(movement_year_month AS VARCHAR(7))  AS movement_year_month,
        CAST(movement_month_name AS VARCHAR(20)) AS movement_month_name,
        CAST(sign_validation_flag AS VARCHAR(50)) AS sign_validation_flag,
        CAST(CASE
            WHEN movement_id IS NULL THEN 'Missing movement ID'
            WHEN store_id_clean IS NULL OR store_id_clean = '' THEN 'Missing store'
            WHEN product_id_clean IS NULL OR product_id_clean = '' THEN 'Missing product'
            WHEN movement_type NOT IN ('SALE','RECEIPT','TRANSFER_IN','TRANSFER_OUT',
                                       'ADJUSTMENT','ADJUSTMENT_IN','ADJUSTMENT_OUT',
                                       'DAMAGE','LOSS','RETURN')
                THEN 'Invalid movement type'
            WHEN quantity_absolute IS NULL OR quantity_absolute = 0 THEN 'Zero/null quantity'
            WHEN unit_cost_kes IS NULL OR unit_cost_kes <= 0 THEN 'Invalid unit cost'
            WHEN running_quantity < 0 THEN 'Negative inventory'
            ELSE 'Valid'
        END AS VARCHAR(50)) AS quality_flag,
        GETDATE() AS etl_load_date,
        CAST('bronze.inventory_movements_raw' AS NVARCHAR(100)) AS etl_source
    INTO silver.inventory_movements
    FROM with_running;


    -- ============================================================
    -- 19. silver.inventory_snapshots
    --     Point-in-time stock on hand per store and product.
    -- ============================================================
    PRINT 'Loading silver.inventory_snapshots...';
    DROP TABLE IF EXISTS silver.inventory_snapshots;

    ;WITH cleaned AS (
        SELECT
            -- Handle date sentinel
            CAST(CASE 
                WHEN snapshot_date = '2023-13-45' THEN '2023-12-25' 
                ELSE snapshot_date 
            END AS DATE) AS snapshot_date_clean,

            -- Strip '-DUP' suffix from store_id
            CAST(CASE 
                WHEN store_id LIKE '%-DUP%' 
                    THEN LEFT(store_id, CHARINDEX('-DUP', store_id) - 1)
                ELSE store_id 
            END AS NVARCHAR(50)) AS store_id_clean,

            -- Strip '-DUP' suffix from product_id (exact removal, not position-based)
            CAST(CASE 
                WHEN product_id LIKE '%-DUP' 
                    THEN REPLACE(product_id, '-DUP', '')
                ELSE product_id 
            END AS NVARCHAR(50)) AS product_id_clean,

            CAST(on_hand_quantity AS INT) AS on_hand_quantity,
            CAST(reorder_point    AS DECIMAL(18,2)) AS reorder_point,
            CAST(safety_stock     AS INT) AS safety_stock

        FROM bronze.inventory_snapshots_raw
        -- Only filter rows where the date itself carries the -DUP suffix
        WHERE snapshot_date NOT LIKE '%-DUP'
    ),

    -- Deduplicate on the natural key: keep the row with the highest on_hand_quantity.
    -- (If two rows exist for the same store-product-date, prefer the populated one.)
    deduplicated AS (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY snapshot_date_clean, store_id_clean, product_id_clean
                ORDER BY on_hand_quantity DESC
            ) AS rn
        FROM cleaned
        WHERE store_id_clean   IS NOT NULL
          AND product_id_clean IS NOT NULL
          AND snapshot_date_clean IS NOT NULL
    )

    SELECT
        ROW_NUMBER() OVER (
            ORDER BY snapshot_date_clean, store_id_clean, product_id_clean
        ) AS inventory_key,

        snapshot_date_clean AS snapshot_date,
        store_id_clean      AS store_id,
        product_id_clean    AS product_id,

        on_hand_quantity,
        reorder_point,
        safety_stock,

        -- Quality flags — useful downstream in Gold
        CAST(CASE
            WHEN on_hand_quantity < 0                              THEN 'Negative on-hand'
            WHEN reorder_point IS NULL OR reorder_point < 0         THEN 'Invalid reorder point'
            WHEN safety_stock IS NULL OR safety_stock < 0           THEN 'Invalid safety stock'
            WHEN on_hand_quantity < safety_stock                    THEN 'Below safety stock'
            WHEN on_hand_quantity < reorder_point                   THEN 'Below reorder point'
            ELSE 'Valid'
        END AS VARCHAR(50)) AS quality_flag,

        -- Stock status — business-friendly classification
        CAST(CASE
            WHEN on_hand_quantity < 0                     THEN 'Negative Stock'
            WHEN on_hand_quantity = 0                     THEN 'Out of Stock'
            WHEN on_hand_quantity < safety_stock          THEN 'Below Safety Stock'
            WHEN on_hand_quantity < reorder_point         THEN 'Below Reorder Point'
            ELSE 'Healthy'
        END AS VARCHAR(30)) AS stock_status,

        -- Useful derived measures
        on_hand_quantity - reorder_point AS units_above_reorder,
        on_hand_quantity - safety_stock  AS units_above_safety,

        GETDATE() AS etl_load_date,
        CAST('bronze.inventory_snapshots_raw' AS NVARCHAR(100)) AS etl_source

    INTO silver.inventory_snapshots
    FROM deduplicated
    WHERE rn = 1;


    -- ============================================================
    -- 20. silver.gis_locations
    --     Points of interest with coordinates and accessibility.
    -- ============================================================
    PRINT 'Loading silver.gis_locations...';
    DROP TABLE IF EXISTS silver.gis_locations;
	WITH main AS (
    SELECT ROW_NUMBER() OVER(PARTITION BY town ORDER BY location_id) flag,
        CAST(location_id   AS NVARCHAR(50))  AS location_id,
        CAST(county        AS NVARCHAR(100)) AS county,
		CAST(town          AS NVARCHAR(100)) AS town,
        CAST(location_name AS NVARCHAR(200)) AS location_name,
        CAST(location_type AS NVARCHAR(50))  AS location_type,
        CAST(latitude      AS DECIMAL(9,6))  AS latitude,
        CAST(longitude     AS DECIMAL(9,6))  AS longitude,
        CAST(accessibility_score AS DECIMAL(9,4)) AS accessibility_score
    FROM bronze.gis_locations_raw) 
	SELECT location_id,county, town,location_name,
	  latitude,longitude, accessibility_score
	  INTO silver.gis_locations
	  FROM main 
	  WHERE flag = 1
	  ;

    -- ============================================================
    -- 21. silver.loyalty_transactions
    --     Loyalty points ledger with running balance per customer
    --     and quality flags for inconsistent redemptions.
    -- ============================================================
    PRINT 'Loading silver.loyalty_transactions...';
    DROP TABLE IF EXISTS silver.loyalty_transactions;

    ;WITH base AS (
        SELECT
            transaction_id,
            LEFT(customer_id, 11) AS customer_id,
            CAST(CASE WHEN [date] = '2023-13-45' THEN '2023-12-25' ELSE [date] END AS DATE) AS transaction_date,
            CAST(points_earned   AS INT) AS points_earned,
            ABS(CAST(points_redeemed AS INT)) AS points_redeemed,
            CAST(points_balance  AS INT) AS points_balance,
            LOWER(TRIM(transaction_type)) AS transaction_type,
            -- Normalize order id to "TXN-NNNN" style
            CASE WHEN order_id LIKE 'TXN%'
                 THEN CONCAT('TXN-', TRIM(SUBSTRING(order_id, CHARINDEX('-', order_id) + 1, 20)))
                 ELSE order_id END AS order_id
        FROM bronze.loyalty_transactions_raw
        WHERE transaction_id IS NOT NULL AND customer_id IS NOT NULL
    ),
    cleaned AS (
        SELECT
            transaction_id, customer_id,
            CASE WHEN customer_id LIKE '%-DUP%'
                 THEN LEFT(customer_id, CHARINDEX('-DUP', customer_id) - 1)
                 ELSE customer_id END AS customer_id_clean,
            transaction_date,
            YEAR(transaction_date)  AS transaction_year,
            MONTH(transaction_date) AS transaction_month,
            DATEPART(QUARTER, transaction_date) AS transaction_quarter,
            FORMAT(transaction_date, 'yyyy-MM') AS transaction_year_month,
            points_earned, points_redeemed, points_balance,
            -- Net change used for the running balance
            CASE WHEN transaction_type = 'redeem' THEN -ABS(points_redeemed) ELSE points_earned END AS points_net_change,
            CASE
                WHEN transaction_type IN ('earn','earning','earned','credit') THEN 'Earn'
                WHEN transaction_type IN ('redeem','redemption','redeemed','debit') THEN 'Redeem'
                WHEN points_earned < 0 THEN 'Adjustment (Negative)'
                WHEN points_redeemed > 0 AND transaction_type = 'earn' THEN 'Mixed - Review'
                ELSE 'Other' END AS transaction_type_clean,
            order_id,
            CASE
                WHEN order_id IS NULL OR order_id = '' THEN 'No linked order'
                WHEN order_id LIKE 'ECORD-%' THEN 'E-commerce order'
                WHEN order_id LIKE 'TXN-%'   THEN 'POS transaction'
                ELSE 'Unknown source' END AS order_source_type,
            CASE
                WHEN points_earned >= 1000 THEN 'High earner (1000+ points)'
                WHEN points_earned >= 500  THEN 'Medium earner (500-999 points)'
                WHEN points_earned >= 100  THEN 'Low earner (100-499 points)'
                WHEN points_earned > 0     THEN 'Small earner (1-99 points)'
                WHEN points_redeemed >= 1000 THEN 'High redemption (1000+ points)'
                ELSE 'No significant activity' END AS points_activity_tier,
            CASE
                WHEN points_balance >= 5000 THEN 'VIP - High points'
                WHEN points_balance >= 1000 THEN 'Active - Good points'
                WHEN points_balance >= 100  THEN 'Low points'
                WHEN points_balance > 0     THEN 'Minimal points'
                WHEN points_balance = 0 AND transaction_type = 'redeem' THEN 'Points exhausted'
                WHEN points_balance < 0     THEN 'Negative balance - Data error'
                ELSE 'No points' END AS customer_point_status,
            CASE
                WHEN transaction_date > GETDATE() THEN 'Future date - Invalid'
                WHEN points_earned < 0 AND transaction_type = 'earn' AND points_redeemed = 0 THEN 'Negative earn - Possible adjustment'
                WHEN points_balance < 0 THEN 'Negative balance - Data error'
                WHEN transaction_type NOT IN ('earn','redeem') THEN 'Invalid transaction type'
                WHEN transaction_type = 'redeem' AND points_redeemed <= 0 THEN 'Invalid redemption amount'
                WHEN transaction_type = 'earn' AND points_earned <= 0 AND points_redeemed = 0 THEN 'No points movement'
                ELSE 'Valid' END AS quality_flag
        FROM base
    ),
    with_running_balance AS (
        SELECT
            *,
            -- Running total per customer, ordered by date
            SUM(points_net_change) OVER (
                PARTITION BY customer_id_clean
                ORDER BY transaction_date, transaction_id, points_net_change
                ROWS UNBOUNDED PRECEDING
            ) AS running_points_balance
        FROM cleaned
    ),
    finalised AS (
        SELECT
            *,
            CASE
                WHEN quality_flag != 'Valid' THEN quality_flag
                -- Business rule: cannot redeem more than earned
                WHEN transaction_type_clean = 'Redeem' AND running_points_balance < 0 THEN 'Redeem exceeds available balance'
                ELSE 'Valid' END AS quality_flag_final
        FROM with_running_balance
    )
    SELECT
        ROW_NUMBER() OVER (ORDER BY customer_id_clean, transaction_date, transaction_id) AS loyalty_transaction_key,
        CAST(transaction_id AS NVARCHAR(50)) AS transaction_id,
        CAST(customer_id_clean AS NVARCHAR(50)) AS customer_id,
        CAST(order_id AS NVARCHAR(50)) AS order_id,
        transaction_date,
        CAST(transaction_type_clean AS VARCHAR(30)) AS transaction_type,
        points_earned, points_redeemed,
        CASE
            WHEN transaction_type_clean = 'Earn'   THEN points_earned
            WHEN transaction_type_clean = 'Redeem' THEN -points_redeemed
            ELSE points_net_change END AS points_change,
        running_points_balance,
        points_balance,
        CAST(order_source_type AS VARCHAR(50)) AS order_source_type,
        CAST(points_activity_tier AS VARCHAR(50)) AS points_activity_tier,
        CAST(customer_point_status AS VARCHAR(50)) AS customer_point_status,
        GETDATE() AS etl_load_date,
        CAST('bronze.loyalty_transactions_raw' AS NVARCHAR(100)) AS etl_source
    INTO silver.loyalty_transactions
    FROM finalised
    WHERE quality_flag_final != 'Future date - Invalid';


    -- ============================================================
    -- 22. silver.pos_line_items
    --     POS transaction lines. Duplicate product lines within
    --     one transaction are merged.
    -- ============================================================
    PRINT 'Loading silver.pos_line_items...';
    DROP TABLE IF EXISTS silver.pos_line_items;

    ;WITH base AS (
        SELECT
            REPLACE(TRIM(transaction_id), ' ', '') AS transaction_id,
            line_number,
            CASE WHEN product_id LIKE '%DUP'
                 THEN SUBSTRING(product_id, 1, CHARINDEX('D', product_id, 5) - 2)
                 ELSE product_id END AS product_id,
            ABS(CAST(quantity AS INT)) AS quantity,
            CAST(ABS(TRY_CAST(unit_price AS DECIMAL(18,2))) AS DECIMAL(18,2)) AS unit_price_kes,
            CAST(ABS(TRY_CAST(discount_rate AS DECIMAL(9,4))) AS DECIMAL(9,4)) AS discount_rate,
            -- Campaign tag embedded in line_total like "CMP1234,5000"
            CASE WHEN line_total LIKE 'CMP%' THEN LEFT(line_total, 8) ELSE '' END AS campaign,
            CAST(ABS(TRY_CAST(CASE
                WHEN TRIM(REPLACE(line_total, ',', '')) LIKE 'CMP%'
                THEN SUBSTRING(TRIM(REPLACE(line_total, ',', '')), 9, 20)
                ELSE TRIM(REPLACE(line_total, ',', ''))
            END AS DECIMAL(18,2))) AS DECIMAL(18,2)) AS line_total
        FROM bronze.pos_line_items_raw
        WHERE transaction_id IS NOT NULL
          AND transaction_id != ''
          AND product_id IS NOT NULL
    ),
    validated AS (
        SELECT
            *,
            CAST(quantity * unit_price_kes * (1 - discount_rate) AS DECIMAL(18,2)) AS calculated_line_total,
            CAST(quantity * unit_price_kes * discount_rate       AS DECIMAL(18,2)) AS discount_amount_kes,
            CAST(unit_price_kes * (1 - discount_rate)            AS DECIMAL(18,2)) AS effective_unit_price_kes,
            CASE WHEN discount_rate = 0    THEN 'No Discount'
                 WHEN discount_rate < 0.05 THEN 'Small Discount (<5%)'
                 WHEN discount_rate < 0.10 THEN 'Standard Discount (5-10%)'
                 WHEN discount_rate < 0.20 THEN 'Large Discount (10-20%)'
                 ELSE 'Heavy Discount (>20%)' END AS discount_tier,
            CASE WHEN line_total >= 500000 THEN 'Premium Line (500K+ KES)'
                 WHEN line_total >= 100000 THEN 'High Value Line (100K-500K)'
                 WHEN line_total >= 50000  THEN 'Medium Value Line (50K-100K)'
                 WHEN line_total >= 10000  THEN 'Low Value Line (10K-50K)'
                 ELSE 'Small Item (<10K KES)' END AS line_value_tier,
            CASE WHEN transaction_id LIKE 'TXN-%' THEN 'POS'
                 WHEN transaction_id LIKE '%-%'   THEN LEFT(transaction_id, CHARINDEX('-', transaction_id) - 1)
                 ELSE 'Unknown' END AS transaction_source,
            CASE WHEN quantity <= 0 THEN 'Invalid quantity'
                 WHEN unit_price_kes <= 0 THEN 'Invalid unit price'
                 WHEN discount_rate < 0 OR discount_rate > 1 THEN 'Invalid discount rate'
                 WHEN line_total <= 0 THEN 'Invalid line total'
                 WHEN ABS(CAST(quantity * unit_price_kes * (1 - discount_rate) AS DECIMAL(18,2)) - line_total) > 0.01 THEN 'Line total mismatch'
                 WHEN transaction_id LIKE '% %' OR transaction_id = '' THEN 'Malformed transaction ID'
                 ELSE 'Valid' END AS quality_flag
        FROM base
    ),
    aggregated AS (
        SELECT
            transaction_id, product_id,
            MIN(line_number) AS line_number,
            SUM(quantity) AS quantity,
            CAST(AVG(unit_price_kes) AS DECIMAL(18,2)) AS unit_price_kes,
            CAST(AVG(discount_rate)  AS DECIMAL(9,4))  AS discount_rate,
            SUM(line_total) AS line_total,
            SUM(CAST(quantity * unit_price_kes * discount_rate AS DECIMAL(18,2))) AS discount_amount_kes,
            CAST(SUM(quantity * unit_price_kes * (1 - discount_rate)) / NULLIF(SUM(quantity), 0) AS DECIMAL(18,2)) AS effective_unit_price_kes,
            CASE
                WHEN COUNT(DISTINCT CASE
                    WHEN discount_rate = 0 THEN 'No Discount'
                    WHEN discount_rate < 0.05 THEN 'Small Discount (<5%)'
                    WHEN discount_rate < 0.10 THEN 'Standard Discount (5-10%)'
                    WHEN discount_rate < 0.20 THEN 'Large Discount (10-20%)'
                    ELSE 'Heavy Discount (>20%)' END) = 1
                THEN MAX(CASE
                    WHEN discount_rate = 0 THEN 'No Discount'
                    WHEN discount_rate < 0.05 THEN 'Small Discount (<5%)'
                    WHEN discount_rate < 0.10 THEN 'Standard Discount (5-10%)'
                    WHEN discount_rate < 0.20 THEN 'Large Discount (10-20%)'
                    ELSE 'Heavy Discount (>20%)' END)
                ELSE 'Mixed Discount Tiers' END AS discount_tier,
            CASE
                WHEN SUM(line_total) >= 500000 THEN 'Premium Line (500K+ KES)'
                WHEN SUM(line_total) >= 100000 THEN 'High Value Line (100K-500K)'
                WHEN SUM(line_total) >= 50000  THEN 'Medium Value Line (50K-100K)'
                WHEN SUM(line_total) >= 10000  THEN 'Low Value Line (10K-50K)'
                ELSE 'Small Item (<10K KES)' END AS line_value_tier,
            MAX(transaction_source) AS transaction_source
        FROM validated
        WHERE quality_flag = 'Valid'
        GROUP BY transaction_id, product_id
    )
    SELECT
        ROW_NUMBER() OVER (ORDER BY transaction_id, line_number) AS pos_line_key,
        CAST(transaction_id AS NVARCHAR(50)) AS transaction_id,
        line_number,
        CAST(product_id AS NVARCHAR(50)) AS product_id,
        quantity, unit_price_kes, discount_rate,
        effective_unit_price_kes, discount_amount_kes, line_total,
        CAST(discount_tier AS VARCHAR(30)) AS discount_tier,
        CAST(line_value_tier AS VARCHAR(30)) AS line_value_tier,
        CAST(transaction_source AS VARCHAR(30)) AS transaction_source,
        GETDATE() AS etl_load_date,
        CAST('bronze.pos_line_items_raw' AS NVARCHAR(100)) AS etl_source
    INTO silver.pos_line_items
    FROM aggregated;


    -- ============================================================
    -- 23. silver.pos_returns
    --     Returns that came through the POS channel (transaction
    --     ids starting with TXN).
    -- ============================================================
    PRINT 'Loading silver.pos_returns...';
    DROP TABLE IF EXISTS silver.pos_returns;

    SELECT
        CAST(return_id AS NVARCHAR(50)) AS return_id,
        CAST(REPLACE(original_transaction_id, ' ', '') AS NVARCHAR(50)) AS original_transaction_id,
        CAST(CASE WHEN return_date = '2023-13-45' THEN '2023-12-25' ELSE return_date END AS DATE) AS return_date,
        CAST(CASE WHEN product_id LIKE '%DUP' THEN LEFT(product_id, 9) ELSE product_id END AS NVARCHAR(50)) AS product_id,
        CAST(quantity_returned AS INT) AS quantity_returned,
        CAST(refund_amount AS DECIMAL(18,2)) AS refund_amount,
        CAST(return_reason AS NVARCHAR(200)) AS return_reason
    INTO silver.pos_returns
    FROM bronze.returns_raw
    WHERE original_transaction_id LIKE 'TXN%'
      AND return_id NOT LIKE '%DUP';


    -- ============================================================
    -- 24. silver.pos_transactions
    --     POS transaction headers. line_total is aggregated from
    --     silver.pos_line_items so it reconciles with the lines.
    -- ============================================================
    PRINT 'Loading silver.pos_transactions...';
    DROP TABLE IF EXISTS silver.pos_transactions;

    ;WITH base AS (
        SELECT
            REPLACE(transaction_id, ' ', '') AS transaction_id,
            transaction_date, store_id, customer_id, cashier_id, payment_method,
            CAST(total_amount AS DECIMAL(18,2)) AS total_amount
        FROM bronze.pos_transactions_raw
        WHERE transaction_id IS NOT NULL
    ),
    cleaned AS (
        SELECT
            b.transaction_id,
            CAST(LEFT(b.transaction_date, 10) AS DATE) AS transaction_date,
            CAST(SUBSTRING(b.transaction_date, 12, 8) AS TIME) AS transaction_time,
            CASE WHEN b.store_id LIKE '%-DUP%' THEN LEFT(b.store_id, CHARINDEX('-DUP', b.store_id) - 1) ELSE b.store_id END AS store_id_clean,
            CASE WHEN b.customer_id IS NULL THEN 'WALK-IN-CUSTOMER'
                 WHEN b.customer_id LIKE '%-DUP%' THEN LEFT(b.customer_id, CHARINDEX('-DUP', b.customer_id) - 1)
                 ELSE b.customer_id END AS customer_id_clean,
            CASE WHEN b.cashier_id LIKE '%-DUP%' THEN LEFT(b.cashier_id, CHARINDEX('-DUP', b.cashier_id) - 1) ELSE b.cashier_id END AS cashier_id_clean,
            CASE WHEN b.payment_method = 'Mixed' THEN 'Mixed (Cash + Card)'
                 WHEN b.payment_method = 'Card' THEN 'Card'
                 WHEN b.payment_method = 'Cash' THEN 'Cash'
                 WHEN b.payment_method = 'Mobile Money' THEN 'Mobile Money'
                 WHEN b.payment_method = 'Cheque' THEN 'Cheque'
                 ELSE 'Other' END AS payment_method_clean,
            b.total_amount,
            YEAR(CAST(LEFT(b.transaction_date, 10) AS DATE))  AS transaction_year,
            MONTH(CAST(LEFT(b.transaction_date, 10) AS DATE)) AS transaction_month,
            DATEPART(QUARTER, CAST(LEFT(b.transaction_date, 10) AS DATE)) AS transaction_quarter,
            FORMAT(CAST(LEFT(b.transaction_date, 10) AS DATE), 'yyyy-MM') AS transaction_year_month,
            DATEPART(HOUR, CAST(SUBSTRING(b.transaction_date, 12, 8) AS TIME)) AS transaction_hour,
            DATEPART(WEEKDAY, CAST(LEFT(b.transaction_date, 10) AS DATE)) AS transaction_weekday_num,
            DATENAME(WEEKDAY, CAST(LEFT(b.transaction_date, 10) AS DATE)) AS transaction_weekday,
            CASE WHEN b.customer_id IS NULL THEN 'Walk-in (Unknown)'
                 WHEN b.customer_id LIKE '%-DUP%' THEN 'Registered (Needs merge)'
                 ELSE 'Registered Customer' END AS customer_type,
            CASE WHEN b.total_amount >= 1000000 THEN 'High Value (1M+ KES)'
                 WHEN b.total_amount >= 500000  THEN 'Medium-High (500K-1M KES)'
                 WHEN b.total_amount >= 100000  THEN 'Medium (100K-500K KES)'
                 WHEN b.total_amount >= 50000   THEN 'Low-Medium (50K-100K KES)'
                 ELSE 'Low Value (<50K KES)' END AS transaction_tier,
            CASE WHEN DATEPART(HOUR, CAST(SUBSTRING(b.transaction_date, 12, 8) AS TIME)) BETWEEN 6 AND 11  THEN 'Morning (6AM-11AM)'
                 WHEN DATEPART(HOUR, CAST(SUBSTRING(b.transaction_date, 12, 8) AS TIME)) BETWEEN 12 AND 16 THEN 'Afternoon (12PM-4PM)'
                 WHEN DATEPART(HOUR, CAST(SUBSTRING(b.transaction_date, 12, 8) AS TIME)) BETWEEN 17 AND 20 THEN 'Evening (5PM-8PM)'
                 ELSE 'Late Night (9PM-5AM)' END AS time_of_day,
            CASE WHEN CAST(LEFT(b.transaction_date, 10) AS DATE) > GETDATE() THEN 'Future date - Invalid'
                 WHEN CAST(LEFT(b.transaction_date, 10) AS DATE) < '2015-01-01' THEN 'Suspicious old date'
                 WHEN b.total_amount <= 0 THEN 'Invalid amount'
                 WHEN b.payment_method NOT IN ('Card','Cash','Mobile Money','Cheque','Mixed') THEN 'Invalid payment method'
                 ELSE 'Valid' END AS quality_flag
        FROM base b
    ),
    lines AS (
        -- Sum line totals from silver.pos_line_items so the header
        -- total matches the detail
        SELECT transaction_id, SUM(line_total) AS line_total
        FROM silver.pos_line_items
        GROUP BY transaction_id
    )
    SELECT
        ROW_NUMBER() OVER (ORDER BY c.transaction_id) AS pos_transaction_key,
        CAST(c.transaction_id AS NVARCHAR(50)) AS transaction_id,
        CAST(c.store_id_clean AS NVARCHAR(50)) AS store_id,
        CAST(c.customer_id_clean AS NVARCHAR(50)) AS customer_id,
        CAST(c.cashier_id_clean AS NVARCHAR(50)) AS cashier_id,
        c.transaction_date,
        c.transaction_time,
        CAST(l.line_total AS DECIMAL(18,2)) AS line_total,
        CAST(c.payment_method_clean AS VARCHAR(50)) AS payment_method,
        CAST(c.transaction_tier AS VARCHAR(50)) AS transaction_tier,
        CAST(c.customer_type AS VARCHAR(50)) AS customer_type,
        CAST(c.time_of_day AS VARCHAR(30)) AS time_of_day,
        c.transaction_year, c.transaction_month, c.transaction_quarter,
        CAST(c.transaction_year_month AS VARCHAR(7)) AS transaction_year_month,
        c.transaction_hour, c.transaction_weekday_num,
        CAST(c.transaction_weekday AS VARCHAR(20)) AS transaction_weekday,
        CAST(c.quality_flag AS VARCHAR(50)) AS quality_flag,
        GETDATE() AS etl_load_date,
        CAST('bronze.pos_transactions_raw' AS NVARCHAR(100)) AS etl_source
    INTO silver.pos_transactions
    FROM cleaned c
    LEFT JOIN lines l ON c.transaction_id = l.transaction_id
    WHERE c.quality_flag != 'Future date - Invalid';


    -- ============================================================
    -- 25. silver.promotion_products
    --     Link table between promotions and products.
    -- ============================================================
    PRINT 'Loading silver.promotion_products...';
    DROP TABLE IF EXISTS silver.promotion_products;

    ;WITH base AS (
        SELECT promotion_id, product_id
        FROM bronze.promotion_products_raw
        WHERE promotion_id IS NOT NULL
    ),
    cleaned AS (
        SELECT
            promotion_id, product_id,
            CONCAT(promotion_id, '_', product_id) AS promotion_product_key,
            CAST(CASE
                WHEN product_id IS NULL OR product_id = '' THEN 'Missing product - Invalid'
                WHEN product_id LIKE '%NULL%' THEN 'NULL value - Invalid'
                ELSE 'Valid' END AS VARCHAR(50)) AS quality_flag,
            CAST(CASE
                WHEN product_id IS NULL OR product_id = '' THEN 'Invalid record (no product)'
                ELSE 'Valid product promotion link' END AS VARCHAR(50)) AS record_type,
            GETDATE() AS etl_load_date,
            CAST('bronze.promotion_products_raw' AS NVARCHAR(100)) AS etl_source
        FROM base
    )
    SELECT
        CAST(promotion_product_key AS NVARCHAR(100)) AS promotion_product_key,
        CAST(promotion_id AS NVARCHAR(50)) AS promotion_id,
        CAST(product_id   AS NVARCHAR(50)) AS product_id,
        record_type, quality_flag, etl_load_date, etl_source
    INTO silver.promotion_products
    FROM cleaned
    WHERE product_id IS NOT NULL AND product_id != 'NULL';


		-- ============================================================
		-- SILVER: silver.products
		-- SCD-2 product dimension source
		-- ============================================================
		DROP TABLE IF EXISTS silver.products;
		CREATE TABLE silver.products (
			product_sk          INT IDENTITY(1,1) PRIMARY KEY,
			product_id          NVARCHAR(50)  NOT NULL,
			product_name        NVARCHAR(200) NULL,
			brand               NVARCHAR(100) NULL,
			category            NVARCHAR(100) NULL,
			subcategory         NVARCHAR(100) NULL,
			supplier_id         NVARCHAR(50)  NULL,
			unit_cost_kes       DECIMAL(18,2) NULL,
			retail_price_kes    DECIMAL(18,2) NULL,
			margin_percentage   DECIMAL(9,2)  NULL,
			margin_band         VARCHAR(20)   NULL,
			introduction_date   DATE          NULL,
			valid_from          DATE          NULL,
			valid_to            DATE          NULL,
			discontinued_date   DATE          NULL,
			is_active           BIT           NULL,
			is_current_version  BIT           NULL
		);
		;WITH main AS (
			SELECT
				ROW_NUMBER() OVER (PARTITION BY 
					CASE WHEN product_id LIKE '%DUP' THEN LEFT(product_id, 9) ELSE product_id END 
					ORDER BY valid_from) AS flag,
				CASE WHEN product_id LIKE '%DUP' THEN LEFT(product_id, 9) ELSE product_id END AS product_id,
				-- Detect whether this is the last version for this product
				LEAD(CASE WHEN product_id LIKE '%DUP' THEN LEFT(product_id, 9) ELSE product_id END)
					OVER (PARTITION BY 
						CASE WHEN product_id LIKE '%DUP' THEN LEFT(product_id, 9) ELSE product_id END 
						ORDER BY valid_from) AS next_product_id,

				product_name, brand, category, subcategory,

				CASE WHEN supplier_id LIKE '%DUP' THEN LEFT(supplier_id, 8) ELSE supplier_id END AS supplier_id_clean,

				CAST(unit_cost_kes     AS DECIMAL(18,2)) AS unit_cost_kes,
				CAST(retail_price_kes  AS DECIMAL(18,2)) AS retail_price_kes,
				CAST(margin_percentage AS DECIMAL(9,2))  AS margin_percentage,

				CASE
					WHEN CAST(margin_percentage AS DECIMAL(9,2)) < 20 THEN 'low'
					WHEN CAST(margin_percentage AS DECIMAL(9,2)) BETWEEN 20 AND 40 THEN 'medium'
					WHEN CAST(margin_percentage AS DECIMAL(9,2)) > 40 THEN 'high'
				END AS margin_band,

				CAST(CASE WHEN valid_from IS NULL THEN GETDATE()
						  WHEN valid_from = '2023-13-45' THEN '2023-12-25'
						  ELSE valid_from END AS DATE) AS valid_from_clean,

				CAST(CASE WHEN introduction_date IS NULL THEN GETDATE()
						  WHEN introduction_date = '2023-13-45' THEN '2023-12-25'
						  ELSE introduction_date END AS DATE) AS introduction_date_clean,

				CAST(CASE WHEN valid_to IS NULL THEN GETDATE()
						  WHEN valid_to = '2023-13-45' THEN '2023-12-25'
						  ELSE valid_to END AS DATE) AS valid_to_clean,

				CAST(CASE WHEN discontinued_date IS NULL THEN GETDATE()
						  WHEN discontinued_date = '2023-13-45' THEN '2023-12-25'
						  ELSE discontinued_date END AS DATE) AS discontinued_date_clean,

				is_active,
				CASE WHEN valid_to IS NULL THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS is_current_version

			FROM bronze.products_raw
		)

		INSERT INTO silver.products (
			product_id, product_name, brand, category, subcategory, supplier_id,
			unit_cost_kes, retail_price_kes, margin_percentage, margin_band,
			introduction_date, valid_from, valid_to, discontinued_date,
			is_active, is_current_version
		)
		SELECT
			product_id,
			product_name,
			brand,
			category,
			subcategory,

			CASE 
				WHEN supplier_id_clean IS NULL AND flag = 1 THEN 'SUP-0018'
				WHEN supplier_id_clean IS NULL AND flag = 2 THEN 'SUP-0060'
				WHEN supplier_id_clean IS NULL AND flag = 3 THEN 'SUP-0145'
				WHEN supplier_id_clean IS NULL AND flag = 4 THEN 'SUP-0178'
				ELSE supplier_id_clean
			END AS supplier_id,

			unit_cost_kes,
			retail_price_kes,
			margin_percentage,
			margin_band,

			CASE WHEN flag = 1 THEN CAST('2016-01-01' AS DATE) 
				 ELSE introduction_date_clean END AS introduction_date,

			CASE WHEN flag = 1 THEN CAST('2016-01-01' AS DATE) 
				 ELSE valid_from_clean END AS valid_from,
			CASE WHEN next_product_id IS NULL THEN CAST(GETDATE() AS DATE)
				 ELSE valid_to_clean END AS valid_to,
			discontinued_date_clean,
			is_active,
			is_current_version
		FROM main;

    -- ============================================================
    -- 27. silver.promotions
    --     Promotion headers with discount description and status.
    -- ============================================================
    PRINT 'Loading silver.promotions...';
    DROP TABLE IF EXISTS silver.promotions;

    ;WITH base AS (
        SELECT
            promotion_id, campaign_id ,promotion_name,
            CAST(start_date AS DATE) AS start_date,
            CAST(end_date   AS DATE) AS end_date,
            LOWER(TRIM(discount_type)) AS discount_type,
            CAST(discount_value AS DECIMAL(18,2)) AS discount_value
        FROM bronze.promotions_raw
        WHERE promotion_id IS NOT NULL
    ),
    cleaned AS (
        SELECT
            promotion_id, campaign_id , promotion_name,
            -- Extract short name from "Promotion_XXXX_NNN" pattern
            CAST(CASE WHEN promotion_name LIKE 'Promotion_%'
                      THEN SUBSTRING(promotion_name, 11, LEN(promotion_name) - 10)
                      ELSE promotion_name END AS NVARCHAR(200)) AS promotion_short_name,
            start_date, end_date,
            DATEDIFF(DAY, start_date, end_date) AS campaign_duration_days,
            CASE
                WHEN start_date > GETDATE() THEN 'Scheduled (Future)'
                WHEN end_date < GETDATE() THEN 'Completed (Past)'
                WHEN start_date <= GETDATE() AND end_date >= GETDATE() THEN 'Active (Ongoing)'
                ELSE 'Unknown' END AS promotion_status,
            CASE
                WHEN discount_type IN ('fixed','amount') THEN 'Fixed Amount (KES)'
                WHEN discount_type IN ('percentage','percent','%') THEN 'Percentage (%)'
                ELSE 'Unknown Type' END AS discount_type_clean,
            discount_value,
            CASE
                WHEN discount_type IN ('fixed','amount') THEN CONCAT('KES ', FORMAT(discount_value, 'N0'), ' off')
                WHEN discount_type IN ('percentage','percent','%') THEN CONCAT(CAST(discount_value AS INT), '% off')
                ELSE 'Unknown discount' END AS discount_description,
            CASE
                WHEN DATEDIFF(DAY, start_date, end_date) <= 7  THEN 'Flash Sale (≤7 days)'
                WHEN DATEDIFF(DAY, start_date, end_date) <= 30 THEN 'Short Campaign (8-30 days)'
                WHEN DATEDIFF(DAY, start_date, end_date) <= 90 THEN 'Standard Campaign (31-90 days)'
                ELSE 'Long Campaign (>90 days)' END AS campaign_length_tier,
            CASE
                WHEN start_date > end_date THEN 'Invalid - Start after end'
                WHEN discount_value <= 0 THEN 'Invalid discount value'
                WHEN discount_type NOT IN ('fixed','percentage','amount','percent','%') THEN 'Invalid discount type'
                WHEN start_date IS NULL OR end_date IS NULL THEN 'Missing dates'
                ELSE 'Valid' END AS quality_flag
        FROM base
    )
    SELECT
        CAST(promotion_id AS NVARCHAR(50)) AS promotion_key,
        CAST(promotion_id AS NVARCHAR(50)) AS promotion_id,
		CAST(campaign_id AS NVARCHAR(50)) AS campaign_id,
        CAST(promotion_name AS NVARCHAR(200)) AS promotion_name,
        promotion_short_name,
        start_date, end_date, campaign_duration_days,
        CAST(promotion_status AS VARCHAR(30)) AS promotion_status,
        CAST(campaign_length_tier AS VARCHAR(50)) AS campaign_length_tier,
        CAST(discount_type_clean AS VARCHAR(30)) AS discount_type,
        discount_value,
        discount_value AS discount_amount_or_percent,
        CAST(discount_description AS NVARCHAR(200)) AS discount_description,
        CAST(CASE WHEN start_date <= GETDATE() AND end_date >= GETDATE() THEN 1 ELSE 0 END AS BIT) AS is_active,
        CASE WHEN start_date > GETDATE() THEN DATEDIFF(DAY, GETDATE(), start_date) ELSE 0 END AS days_until_start,
        CASE WHEN end_date   < GETDATE() THEN DATEDIFF(DAY, end_date, GETDATE())   ELSE 0 END AS days_since_ended,
        CAST(quality_flag AS VARCHAR(50)) AS quality_flag,
        GETDATE() AS etl_load_date,
        CAST('bronze.promotions_raw' AS NVARCHAR(100)) AS etl_source
    INTO silver.promotions
    FROM cleaned
    WHERE quality_flag = 'Valid' AND promotion_id NOT LIKE '%DUP';


    -- ============================================================
    -- 28. silver.purchase_order_lines
    --     PO line detail with landed cost and VAT estimates.
    --     Duplicate product lines within a PO are merged.
    -- ============================================================
    PRINT 'Loading silver.purchase_order_lines...';
    DROP TABLE IF EXISTS silver.purchase_order_lines;

    ;WITH base AS (
        SELECT
            po_number, line_number,
            CASE WHEN product_id LIKE '%DUP'
                 THEN LEFT(product_id, CHARINDEX('-', product_id, 6) - 1)
                 ELSE product_id END AS product_id,
            CAST(quantity_ordered AS INT) AS quantity_ordered,
            CAST(ABS(TRY_CAST(unit_price AS DECIMAL(18,2))) AS DECIMAL(18,2)) AS unit_price_kes,
            CAST(ABS(TRY_CAST(line_total AS DECIMAL(18,2))) AS DECIMAL(18,2)) AS line_total_kes,
            CAST(ABS(TRY_CAST(quantity_ordered AS DECIMAL(18,2)) * TRY_CAST(unit_price AS DECIMAL(18,2))) AS DECIMAL(18,2)) AS calculated_line_total
        FROM bronze.purchase_order_lines_raw
        WHERE po_number IS NOT NULL AND product_id IS NOT NULL
    ),
    validated AS (
        SELECT
            *,
            CASE
                WHEN quantity_ordered <= 0 THEN 'Invalid quantity'
                WHEN unit_price_kes <= 0 THEN 'Invalid unit price'
                WHEN line_total_kes <= 0 THEN 'Invalid line total'
                WHEN calculated_line_total != line_total_kes THEN 'Line total mismatch'
                ELSE 'Valid' END AS quality_flag,
            LEFT(po_number, 2) AS po_prefix,
            TRY_CAST(RIGHT(po_number, 8) AS INT) AS po_sequence_number,
            CONCAT(po_number, '_', line_number) AS po_line_key,
            CAST(line_total_kes / NULLIF(quantity_ordered, 0) AS DECIMAL(18,2)) AS calculated_unit_price,
            -- Landed cost = line total * 1.10
            CAST(line_total_kes * 1.10 AS DECIMAL(18,2)) AS landed_cost_kes,
            -- Estimated VAT = line total * 16% (Kenya standard rate)
            CAST(line_total_kes * 0.16 AS DECIMAL(18,2)) AS estimated_vat_kes
        FROM base
    ),
    dedup AS (
        SELECT
            po_line_key, po_number, line_number, product_id,
            quantity_ordered, unit_price_kes, line_total_kes,
            calculated_unit_price, landed_cost_kes, estimated_vat_kes,
            po_prefix, po_sequence_number, quality_flag,
            GETDATE() AS etl_load_date,
            CAST('bronze.purchase_order_lines_raw' AS NVARCHAR(100)) AS etl_source
        FROM validated
        WHERE po_number NOT LIKE '%DUP'
    ),
    aggregated AS (
        SELECT
            po_number, product_id,
            SUM(quantity_ordered)  AS quantity_ordered,
            SUM(line_total_kes)    AS line_total_kes,
            SUM(landed_cost_kes)   AS landed_cost_kes,
            SUM(estimated_vat_kes) AS estimated_vat_kes,
            MAX(unit_price_kes)    AS unit_price_kes,
            MAX(calculated_unit_price) AS calculated_unit_price,
            MAX(po_prefix) AS po_prefix,
            MAX(po_sequence_number) AS po_sequence_number,
            CASE WHEN COUNT(CASE WHEN quality_flag != 'Valid' THEN 1 END) > 0
                 THEN 'Contains Invalid Lines' ELSE 'Valid' END AS quality_flag,
            MAX(etl_load_date) AS etl_load_date,
            MAX(etl_source)    AS etl_source
        FROM dedup
        GROUP BY po_number, product_id
    )
    SELECT
        CAST(CONCAT(po_number, '_', ROW_NUMBER() OVER (PARTITION BY po_number ORDER BY product_id)) AS NVARCHAR(100)) AS po_line_key,
        CAST(po_number AS NVARCHAR(50)) AS po_number,
        ROW_NUMBER() OVER (PARTITION BY po_number ORDER BY product_id) AS line_number,
        CAST(product_id AS NVARCHAR(50)) AS product_id,
        quantity_ordered, unit_price_kes, line_total_kes,
        calculated_unit_price, landed_cost_kes, estimated_vat_kes,
        CAST(po_prefix AS VARCHAR(10)) AS po_prefix,
        po_sequence_number,
        CAST(quality_flag AS VARCHAR(30)) AS quality_flag,
        etl_load_date, etl_source
    INTO silver.purchase_order_lines
    FROM aggregated;


    -- ============================================================
    -- 29. silver.purchase_orders
    --     PO headers with aging, priority, and status category.
    -- ============================================================
    PRINT 'Loading silver.purchase_orders...';
    DROP TABLE IF EXISTS silver.purchase_orders;

    ;WITH base AS (
        SELECT
            po_number,
            CAST(CASE WHEN order_date = '2023-13-45' THEN '2022-10-15' ELSE order_date END AS DATE) AS order_date,
            CASE WHEN supplier_id LIKE '%-DUP%' THEN LEFT(supplier_id, CHARINDEX('-DUP', supplier_id) - 1) ELSE supplier_id END AS supplier_id_clean,
            CAST(CASE WHEN expected_delivery_date = '2023-13-45' THEN '2022-10-15' ELSE expected_delivery_date END AS DATE) AS expected_delivery_date,
            status,
            CAST(ABS(TRY_CAST(total_amount AS DECIMAL(18,2))) AS DECIMAL(18,2)) AS total_amount_kes
        FROM bronze.purchase_orders_raw
        WHERE po_number IS NOT NULL
    ),
    calculated AS (
        SELECT
            *,
            LEFT(po_number, 2) AS po_prefix,
            TRY_CAST(RIGHT(po_number, 8) AS INT) AS po_sequence_number,
            YEAR(order_date)  AS order_year,
            MONTH(order_date) AS order_month,
            DATEPART(QUARTER, order_date) AS order_quarter,
            FORMAT(order_date, 'yyyy-MM') AS order_year_month,
            DATEDIFF(DAY, order_date, expected_delivery_date) AS expected_lead_time_days,
            CASE WHEN status = 'Closed' THEN 'Completed'
                 WHEN status = 'Open' THEN 'In Progress'
                 WHEN status = 'Cancelled' THEN 'Cancelled'
                 ELSE 'Unknown' END AS status_category,
            DATEDIFF(DAY, order_date, GETDATE()) AS days_since_order,
            CASE
                WHEN total_amount_kes <= 0 THEN 'Invalid total amount'
                WHEN order_date > expected_delivery_date THEN 'Order date after expected delivery'
                WHEN order_date IS NULL THEN 'Missing order date'
                WHEN expected_delivery_date IS NULL THEN 'Missing expected delivery date'
                WHEN supplier_id_clean IS NULL OR supplier_id_clean = '' THEN 'Missing supplier'
                WHEN status NOT IN ('Closed','Open','Cancelled') THEN 'Invalid status'
                ELSE 'Valid' END AS quality_flag
        FROM base
    )
    SELECT
        CAST(po_number AS NVARCHAR(50)) AS purchase_order_key,
        CAST(supplier_id_clean AS NVARCHAR(50)) AS supplier_id,
        CAST(status AS NVARCHAR(20)) AS status,
        CAST(status_category AS VARCHAR(30)) AS status_category,
        order_date, expected_delivery_date, total_amount_kes,
        order_year, order_month, order_quarter,
        CAST(order_year_month AS VARCHAR(7)) AS order_year_month,
        expected_lead_time_days, days_since_order,
        CAST(po_prefix AS VARCHAR(10)) AS po_prefix,
        po_sequence_number,
        CAST(CASE
            WHEN status = 'Open' AND DATEDIFF(DAY, order_date, GETDATE()) > 30 THEN 'OVERDUE - Review'
            WHEN status = 'Open' AND DATEDIFF(DAY, order_date, GETDATE()) > 14 THEN 'Pending - Follow up'
            WHEN status = 'Cancelled' THEN 'Cancelled - Investigate'
            WHEN status = 'Closed' THEN 'Complete'
            ELSE 'Normal' END AS VARCHAR(30)) AS action_priority,
        CAST(quality_flag AS VARCHAR(50)) AS quality_flag,
        GETDATE() AS etl_load_date,
        CAST('bronze.purchase_orders_raw' AS NVARCHAR(100)) AS etl_source
    INTO silver.purchase_orders
    FROM calculated
    WHERE order_date IS NOT NULL AND po_number NOT LIKE '%DUP';


    -- ============================================================
    -- 30. silver.sales_returns
    --     Unified returns (POS + e-commerce) with source_channel
    --     tagging. No gold dependency — gold joins on product_id.
    -- ============================================================
    PRINT 'Loading silver.sales_returns...';
    DROP TABLE IF EXISTS silver.sales_returns;

    SELECT
        CAST(return_id AS NVARCHAR(50)) AS return_id,
        CAST(original_transaction_id AS NVARCHAR(50)) AS original_transaction_id,
        CAST(product_id AS NVARCHAR(50)) AS product_id,
        return_date,
        quantity_returned,
        refund_amount,
        CAST(return_reason AS NVARCHAR(200)) AS return_reason,
        CAST('POS' AS VARCHAR(20)) AS source_channel
    INTO silver.sales_returns
    FROM silver.pos_returns

    UNION ALL

    SELECT
        CAST(return_id AS NVARCHAR(50)),
        CAST(original_transaction_id AS NVARCHAR(50)),
        CAST(product_id AS NVARCHAR(50)),
        return_date,
        quantity_returned,
        refund_amount,
        CAST(return_reason AS NVARCHAR(200)),
        CAST('E-Commerce' AS VARCHAR(20))
    FROM silver.ecomerce_returns;


    -- ============================================================
    -- 31. silver.store_daily_financials
    --     Daily P&L per store.
    -- ============================================================
    PRINT 'Loading silver.store_daily_financials...';
    DROP TABLE IF EXISTS silver.store_daily_financials;

    SELECT
        CAST(store_id AS NVARCHAR(50)) AS store_id,
        CAST([date] AS DATE) AS [date],
        CAST(sales_kes          AS DECIMAL(18,2)) AS sales_kes,
        CAST(cost_of_goods_sold AS DECIMAL(18,2)) AS cost_of_goods_sold,
        CAST(gross_margin       AS DECIMAL(18,2)) AS gross_margin,
        CAST(operating_expenses AS DECIMAL(18,2)) AS operating_expenses,
        CAST(net_profit         AS DECIMAL(18,2)) AS net_profit
    INTO silver.store_daily_financials
    FROM bronze.store_daily_financials_raw;


    -- ============================================================
    -- 32. silver.stores
    --     Store master with SCD-style date columns, cleaned name,
    --     and town parsed from the store name.
    -- ============================================================
    PRINT 'Loading silver.stores...';
    DROP TABLE IF EXISTS silver.stores;

    SELECT
        ROW_NUMBER() OVER (ORDER BY store_id, valid_from) AS store_key,
        CAST(store_id AS NVARCHAR(50)) AS store_id,
        CAST(CASE WHEN valid_from IS NULL THEN GETDATE()
                  WHEN valid_from = '2023-13-45' THEN '2023-12-25'
                  ELSE valid_from END AS DATE) AS valid_from,
        CAST(CASE WHEN valid_to IS NULL THEN GETDATE()
                  WHEN valid_to = '2023-13-45' THEN '2023-12-25'
                  ELSE valid_to END AS DATE) AS valid_to,
        -- Replace brand prefix with short form
        CAST(REPLACE(store_name, 'Blue Canopy', 'bc_') AS NVARCHAR(200)) AS store_name,
        CAST(county AS NVARCHAR(100)) AS county,
        -- Extract the town portion from the cleaned store name
        CAST(SUBSTRING(REPLACE(store_name, 'Blue Canopy', 'bc_'), 4, 20) AS NVARCHAR(50)) AS town,
        CAST(COALESCE(format, LAG(format) OVER (ORDER BY store_id)) AS NVARCHAR(50)) AS format,
        CAST(size_sqm AS INT) AS size_sqm,
        CAST(CASE WHEN opening_date = '2023-13-45' THEN '2023-12-25' ELSE opening_date END AS DATE) AS opening_date,
        CAST(CASE WHEN closing_date IS NULL THEN GETDATE()
                  WHEN closing_date = '2023-13-45' THEN '2023-12-25'
                  ELSE closing_date END AS DATE) AS closing_date,
        CAST(CASE WHEN is_active = 'TRUE' THEN 1 ELSE 0 END AS BIT) AS is_active
    INTO silver.stores
    FROM bronze.stores_raw
    WHERE store_id NOT LIKE '%DUP';


    -- ============================================================
    -- 33. silver.suppliers
    --     Supplier master with cleaned phone and email.
    -- ============================================================
    PRINT 'Loading silver.suppliers...';
    DROP TABLE IF EXISTS silver.suppliers;

    SELECT
        CAST(supplier_id AS NVARCHAR(50)) AS supplier_id,
        CAST(CASE WHEN valid_from = '2023-13-45' THEN '2016-01-01' ELSE valid_from END AS DATE) AS valid_from,
        CAST(CASE WHEN valid_to = '2023-13-45' THEN '2016-01-01'
                  WHEN valid_to IS NULL THEN GETDATE()
                  ELSE valid_to END AS DATE) AS valid_to,
        CAST(supplier_name AS NVARCHAR(200)) AS supplier_name,
        CAST(COALESCE(contact_person, supplier_name) AS NVARCHAR(200)) AS contact_person,
        -- Strip international prefix to leave local format
        CAST(REPLACE(phone, '+254', '') AS VARCHAR(50)) AS phone,
        -- Replace placeholder 'contact' with supplier initials
        CAST(REPLACE(email, 'contact', LOWER(LEFT(supplier_name, 2))) AS VARCHAR(255)) AS email,
        CAST(payment_terms AS NVARCHAR(100)) AS payment_terms,
        CAST(lead_time_days AS INT) AS lead_time_days,
        CAST(category AS NVARCHAR(100)) AS category,
        CAST(tax_id AS NVARCHAR(50)) AS tax_id
    INTO silver.suppliers
    FROM bronze.suppliers_raw
    WHERE supplier_id NOT LIKE '%DUP';


    -- ============================================================
    -- Done
    -- ============================================================
    PRINT CONCAT('Silver layer loaded successfully in ',
                 DATEDIFF(SECOND, @StartTime, SYSDATETIME()), ' seconds.');
END;
