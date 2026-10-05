WITH base AS (
    SELECT 
        [promotion_id],
        [promotion_name],
        CAST([start_date] AS DATE) AS start_date,
        CAST([end_date] AS DATE) AS end_date,
        LOWER(TRIM([discount_type])) AS discount_type,
        CAST([discount_value] AS FLOAT) AS discount_value
    FROM [Blue_canopy].[bronze].[promotions_raw]
    WHERE [promotion_id] IS NOT NULL
),

cleaned AS (
    SELECT 
        -- Core identifiers
        promotion_id,
        
        -- Promotion name (clean up placeholder text)
        promotion_name,
        -- Extract meaningful part if needed (e.g., "Promotion_Tempore_754" -> "Tempore")
        CASE 
            WHEN promotion_name LIKE 'Promotion_%' 
            THEN SUBSTRING(promotion_name, 11, LEN(promotion_name) - 10)
            ELSE promotion_name
        END AS promotion_short_name,
        
        -- Dates
        start_date,
        end_date,
        DATEDIFF(DAY, start_date, end_date) AS campaign_duration_days,
        
        -- Promotion status based on current date
        CASE 
            WHEN start_date > GETDATE() THEN 'Scheduled (Future)'
            WHEN end_date < GETDATE() THEN 'Completed (Past)'
            WHEN start_date <= GETDATE() AND end_date >= GETDATE() THEN 'Active (Ongoing)'
            ELSE 'Unknown'
        END AS promotion_status,
        
        -- Discount type standardization
        CASE 
            WHEN discount_type IN ('fixed', 'Fixed', 'FIXED', 'amount', 'Amount') THEN 'Fixed Amount (KES)'
            WHEN discount_type IN ('percentage', 'Percentage', 'PERCENTAGE', 'percent', '%') THEN 'Percentage (%)'
            ELSE 'Unknown Type'
        END AS discount_type_clean,
        
        -- Discount value
        discount_value,
        
        -- Calculate discount impact (percentage vs fixed)
        CASE 
            WHEN discount_type IN ('fixed', 'Fixed', 'FIXED') THEN discount_value
            WHEN discount_type IN ('percentage', 'Percentage', 'PERCENTAGE') THEN discount_value
            ELSE NULL
        END AS discount_amount_or_percent,
        
        -- Create discount description for reporting
        CASE 
            WHEN discount_type IN ('fixed', 'Fixed', 'FIXED') 
            THEN CONCAT('KES ', FORMAT(discount_value, 'N0'), ' off')
            WHEN discount_type IN ('percentage', 'Percentage', 'PERCENTAGE') 
            THEN CONCAT(CAST(discount_value AS INT), '% off')
            ELSE 'Unknown discount'
        END AS discount_description,
        
        -- Campaign duration tier
        CASE 
            WHEN DATEDIFF(DAY, start_date, end_date) <= 7 THEN 'Flash Sale (≤7 days)'
            WHEN DATEDIFF(DAY, start_date, end_date) <= 30 THEN 'Short Campaign (8-30 days)'
            WHEN DATEDIFF(DAY, start_date, end_date) <= 90 THEN 'Standard Campaign (31-90 days)'
            ELSE 'Long Campaign (>90 days)'
        END AS campaign_length_tier,
        
        -- Data quality flags
        CASE 
            WHEN start_date > end_date THEN 'Invalid - Start after end'
            WHEN discount_value <= 0 THEN 'Invalid discount value'
            WHEN discount_type NOT IN ('fixed', 'percentage', 'Fixed', 'Percentage') THEN 'Invalid discount type'
            WHEN start_date IS NULL OR end_date IS NULL THEN 'Missing dates'
            ELSE 'Valid'
        END AS quality_flag
        
    FROM base
)

SELECT 
    -- Surrogate key
    promotion_id AS promotion_key,
    
    -- Identifiers
    promotion_id,
    promotion_name,
    promotion_short_name,
    
    -- Dates
    start_date,
    end_date,
    campaign_duration_days,
    promotion_status,
    campaign_length_tier,
    
    -- Discount details
    discount_type_clean AS discount_type,
    discount_value,
    discount_amount_or_percent,
    discount_description,
    
    -- Active flag (for current promotions)
    CASE 
        WHEN start_date <= GETDATE() AND end_date >= GETDATE() THEN 1
        ELSE 0
    END AS is_active,
    
    -- Days until start (for planning)
    CASE 
        WHEN start_date > GETDATE() THEN DATEDIFF(DAY, GETDATE(), start_date)
        ELSE 0
    END AS days_until_start,
    
    -- Days since ended (for analysis)
    CASE 
        WHEN end_date < GETDATE() THEN DATEDIFF(DAY, end_date, GETDATE())
        ELSE 0
    END AS days_since_ended,
    
    -- Quality
    quality_flag,
    
    -- Audit
    GETDATE() AS etl_load_date,
    'silver.promotions' AS etl_source
    
INTO silver.promotions
FROM cleaned
WHERE quality_flag = 'Valid'
ORDER BY start_date DESC
