-- ===================================================================
-- SILVER LAYER: CRM DATA TRANSFORMATION (Preserve ID Format)
-- ===================================================================

DECLARE @start DATE = '1978-01-01';
DECLARE @end DATE = '2010-12-31';
DECLARE @date_span INT = DATEDIFF(DAY, @start, @end) + 1;

-- Drop and recreate the silver table
DROP TABLE IF EXISTS Blue_canopy.silver.crm;

CREATE TABLE Blue_canopy.silver.crm (
    customer_id NVARCHAR(50) PRIMARY KEY,
    first_name NVARCHAR(100),
    last_name NVARCHAR(100),
    full_name NVARCHAR(201),
    gender VARCHAR(20),
    birth_date DATE,
    age INT,
    age_band VARCHAR(20),
    phone VARCHAR(50),
    email VARCHAR(255),
    county VARCHAR(100),
    town VARCHAR(100),
    customer_segment VARCHAR(50),
    acquisition_channel VARCHAR(50),
    registration_date DATE,
    churn_date DATE,
    loyalty_tier VARCHAR(50),
    communication_preferences VARCHAR(100),
    feedback_score DECIMAL(5,2),
    home_county VARCHAR(100),
    primary_store_id NVARCHAR(50),  -- Changed to NVARCHAR to match store_id format
    is_churned BIT,
    tenure_days INT,
    tenure_months INT,
    tenure_band VARCHAR(30),
    registration_year INT,
    registration_month INT,
    registration_quarter INT,
    email_domain VARCHAR(100),
    phone_prefix VARCHAR(10),
    is_phone_valid BIT,
    is_email_valid BIT,
    created_date DATETIME2 DEFAULT GETDATE(),
    updated_date DATETIME2 DEFAULT GETDATE()
);

-- Insert transformed data
WITH 
-- First, remove duplicates by keeping the first occurrence of each customer_id
deduplicated AS (
    SELECT 
        customer_id,
        first_name,
        last_name,
        gender,
        birth_date,
        phone,
        email,
        county,
        town,
        customer_segment,
        acquisition_channel,
        registration_date,
        churn_date,
        loyalty_tier,
        communication_preferences,
        feedback_score,
        ROW_NUMBER() OVER(
            PARTITION BY customer_id
            ORDER BY 
                CASE WHEN churn_date IS NULL THEN 1 ELSE 2 END,
                registration_date DESC
        ) AS row_num
    FROM Blue_canopy.bronze.crm_raw
    WHERE customer_id NOT LIKE '%DUP%'
      AND customer_id IS NOT NULL
),
-- Clean the data after deduplication
cleaned AS (
    SELECT 
        customer_id,
        first_name = TRIM(UPPER(LEFT(LOWER(first_name), 1)) + LOWER(SUBSTRING(first_name, 2, LEN(first_name)))),
        last_name = TRIM(UPPER(LEFT(LOWER(last_name), 1)) + LOWER(SUBSTRING(last_name, 2, LEN(last_name)))),
        gender = CASE 
                     WHEN (len(first_name) + len(last_name))%2 = 1 THEN 'Male'
                     ELSE 'Female'
                 END,
        raw_birth_date = birth_date,
        raw_registration_date = registration_date,
        raw_churn_date = churn_date,
        phone = TRIM(REPLACE(REPLACE(REPLACE(phone, ' ', ''), '-', ''), '+', '')),
        email = TRIM(LOWER(replace(email,'example','gmail'))),
        county = TRIM(UPPER(LEFT(county, 1)) + LOWER(SUBSTRING(county, 2, LEN(county)))),
        town = TRIM(UPPER(LEFT(town, 1)) + LOWER(SUBSTRING(town, 2, LEN(town)))),
        customer_segment = CASE 
            WHEN customer_segment IN ('Platinum', 'Gold', 'Silver', 'Bronze') THEN customer_segment
            ELSE 'Standard'
        END,
        acquisition_channel = CASE 
            WHEN acquisition_channel IN ('Online', 'Store', 'Referral', 'Social Media', 'Email') THEN acquisition_channel
            ELSE 'Other'
        END,
        loyalty_tier = CASE 
            WHEN loyalty_tier IN ('Platinum', 'Gold', 'Silver', 'Bronze') THEN loyalty_tier
            ELSE 'Bronze'
        END,
        communication_preferences = COALESCE(communication_preferences, 'Email'),
        feedback_score = TRY_CAST(feedback_score AS DECIMAL(5,2)),
        random_days = ABS(CHECKSUM(NEWID())) % @date_span
    FROM deduplicated
    WHERE row_num = 1
),
-- Convert dates
date_converted AS (
    SELECT 
        *,
        clean_birth_date = CASE 
            WHEN ISDATE(raw_birth_date) = 1 
                 AND raw_birth_date NOT LIKE '%[^0-9-]%'
                 AND raw_birth_date NOT IN ('2023-13-45', '1900-01-01')
            THEN CAST(raw_birth_date AS DATE)
            ELSE DATEADD(DAY, random_days, @start)
        END,
        clean_registration_date = CASE 
            WHEN ISDATE(raw_registration_date) = 1 
                 AND raw_registration_date NOT LIKE '%[^0-9-]%'
                 AND raw_registration_date NOT IN ('2023-13-45', '1900-01-01')
            THEN CAST(raw_registration_date AS DATE)
            ELSE DATEADD(DAY, random_days, @start)
        END,
        clean_churn_date = CASE 
            WHEN raw_churn_date IS NULL THEN NULL
            WHEN ISDATE(raw_churn_date) = 1 
                 AND raw_churn_date NOT LIKE '%[^0-9-]%'
                 AND raw_churn_date NOT IN ('2023-13-45', '1900-01-01')
            THEN CAST(raw_churn_date AS DATE)
            ELSE DATEADD(DAY, random_days, @start)
        END
    FROM cleaned
),
-- Calculate primary store and home county for each customer
customer_primary_store AS (
    SELECT 
        c.customer_id,
        p.store_id AS primary_store_id,  -- Keep as string
        s.county AS home_county,
        ROW_NUMBER() OVER(
            PARTITION BY c.customer_id 
            ORDER BY COUNT(*) DESC, p.store_id
        ) AS rank
    FROM date_converted c
    INNER JOIN Blue_canopy.bronze.pos_transactions_raw p 
        ON c.customer_id = p.customer_id
    INNER JOIN Blue_canopy.bronze.stores_raw s 
        ON p.store_id = s.store_id  -- Both are strings now
    GROUP BY 
        c.customer_id, 
        p.store_id, 
        s.county
),
-- Final data with all columns populated
final_data AS (
    SELECT 
        dc.customer_id,
        dc.first_name,
        dc.last_name,
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
        CASE 
            WHEN LEN(dc.phone) = 9 AND dc.phone LIKE '7%' THEN CONCAT('07', dc.phone)
            WHEN LEN(dc.phone) = 9 AND dc.phone LIKE '1%' THEN CONCAT('01', dc.phone)
            WHEN LEN(dc.phone) = 10 AND dc.phone LIKE '07%' THEN dc.phone
            WHEN LEN(dc.phone) = 12 AND dc.phone LIKE '2547%' THEN CONCAT('0', RIGHT(dc.phone, 9))
            ELSE dc.phone
        END AS phone,
        dc.email,
        dc.county,
        dc.town,
        dc.customer_segment,
        dc.acquisition_channel,
        dc.clean_registration_date AS registration_date,
        dc.clean_churn_date AS churn_date,
        dc.loyalty_tier,
        dc.communication_preferences,
        dc.feedback_score,
        -- Get primary store and home county from the CTE
        COALESCE(cps.home_county, 'Unknown') AS home_county,
        cps.primary_store_id,
        CASE 
            WHEN dc.clean_churn_date IS NOT NULL AND dc.clean_churn_date <= GETDATE() THEN 1 
            ELSE 0 
        END AS is_churned,
        DATEDIFF(DAY, dc.clean_registration_date, ISNULL(dc.clean_churn_date, GETDATE())) AS tenure_days,
        DATEDIFF(MONTH, dc.clean_registration_date, ISNULL(dc.clean_churn_date, GETDATE())) AS tenure_months,
        CASE 
            WHEN DATEDIFF(DAY, dc.clean_registration_date, ISNULL(dc.clean_churn_date, GETDATE())) < 30 THEN 'New (<30 days)'
            WHEN DATEDIFF(DAY, dc.clean_registration_date, ISNULL(dc.clean_churn_date, GETDATE())) < 90 THEN 'Recent (30-90 days)'
            WHEN DATEDIFF(DAY, dc.clean_registration_date, ISNULL(dc.clean_churn_date, GETDATE())) < 180 THEN 'Regular (3-6 months)'
            WHEN DATEDIFF(DAY, dc.clean_registration_date, ISNULL(dc.clean_churn_date, GETDATE())) < 365 THEN 'Established (6-12 months)'
            ELSE 'Loyal (>1 year)'
        END AS tenure_band,
        YEAR(dc.clean_registration_date) AS registration_year,
        MONTH(dc.clean_registration_date) AS registration_month,
        DATEPART(QUARTER, dc.clean_registration_date) AS registration_quarter,
        CASE 
            WHEN dc.email IS NOT NULL AND CHARINDEX('@', dc.email) > 0 
            THEN RIGHT(dc.email, LEN(dc.email) - CHARINDEX('@', dc.email))
            ELSE NULL 
        END AS email_domain,
        LEFT(dc.phone, 3) AS phone_prefix,
        CASE WHEN LEN(dc.phone) BETWEEN 10 AND 12 AND dc.phone NOT LIKE '%[^0-9]%' THEN 1 ELSE 0 END AS is_phone_valid,
        CASE WHEN dc.email LIKE '%_@__%.__%' THEN 1 ELSE 0 END AS is_email_valid,
        dc.random_days
    FROM date_converted dc
    LEFT JOIN customer_primary_store cps 
        ON dc.customer_id = cps.customer_id 
        AND cps.rank = 1
)
INSERT INTO Blue_canopy.silver.crm (
    customer_id, first_name, last_name, full_name, gender, birth_date, age, age_band,
    phone, email, county, town, customer_segment, acquisition_channel,
    registration_date, churn_date, loyalty_tier, communication_preferences, feedback_score,
    home_county, primary_store_id, is_churned, tenure_days, tenure_months, tenure_band,
    registration_year, registration_month, registration_quarter, email_domain,
    phone_prefix, is_phone_valid, is_email_valid
)
SELECT 
    customer_id,
    first_name,
    last_name,
    full_name,
    gender,
    birth_date,
    age,
    age_band,
    phone,
    email,
    county,
    town,
    customer_segment,
    acquisition_channel,
    registration_date,
    churn_date,
    loyalty_tier,
    communication_preferences,
    feedback_score,
    home_county,
    primary_store_id,
    is_churned,
    tenure_days,
    tenure_months,
    tenure_band,
    registration_year,
    registration_month,
    registration_quarter,
    email_domain,
    phone_prefix,
    is_phone_valid,
    is_email_valid
FROM final_data
WHERE customer_id IS NOT NULL;

-- Verify the results
SELECT 
    COUNT(*) AS total_customers,
    SUM(CASE WHEN primary_store_id IS NOT NULL THEN 1 ELSE 0 END) AS customers_with_primary_store,
    SUM(CASE WHEN home_county != 'Unknown' THEN 1 ELSE 0 END) AS customers_with_home_county,
    SUM(CASE WHEN primary_store_id IS NULL THEN 1 ELSE 0 END) AS customers_without_transactions
FROM Blue_canopy.silver.crm;

-- Sample of the data
SELECT TOP 100 
    customer_id,
    first_name,
    last_name,
    primary_store_id,
    home_county,
    tenure_band
FROM Blue_canopy.silver.crm
ORDER BY customer_id;
