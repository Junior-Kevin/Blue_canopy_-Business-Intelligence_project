
DROP TABLE IF EXISTS silver.feedback;
GO
WITH base AS (
    SELECT 
        [feedback_id],
        [customer_id],
        CAST([date] AS DATE) date,
        CAST([rating] AS INT) AS rating,
        [category]
    FROM [Blue_canopy].[bronze].[feedback_raw]
    WHERE [feedback_id] IS NOT NULL
),

cleaned AS (
    SELECT 
        -- Core identifiers
        feedback_id,
        
        -- Clean customer_id (consistent with other tables)
        CASE 
            WHEN customer_id LIKE '%-DUP%' THEN LEFT(customer_id, CHARINDEX('-DUP', customer_id) - 1)
            ELSE customer_id
        END AS customer_id_clean,
        
        -- Date handling (flag future dates)
        CAST(date AS DATE) AS feedback_date,
        YEAR(date) AS feedback_year,
        MONTH(date) AS feedback_month,
        DATEPART(QUARTER, date) AS feedback_quarter,
        FORMAT(date, 'yyyy-MM') AS feedback_year_month,
        
        -- Rating (already integer 1-5)
        rating,
        
        -- Category (standardize)
        TRIM(category) AS category_clean,
      
        -- Sentiment categorization based on rating
        CASE 
            WHEN rating >= 4 THEN 'Positive'
            WHEN rating = 3 THEN 'Neutral'
            WHEN rating <= 2 THEN 'Negative'
            ELSE 'Unknown'
        END AS sentiment,
        
        -- Rating group for analysis
        CASE 
            WHEN rating = 5 THEN 'Excellent'
            WHEN rating = 4 THEN 'Good'
            WHEN rating = 3 THEN 'Average'
            WHEN rating = 2 THEN 'Poor'
            WHEN rating = 1 THEN 'Very Poor'
            ELSE 'Invalid'
        END AS rating_label,
        
        -- Data quality flags
        CASE 
            WHEN rating < 1 OR rating > 5 THEN 'Invalid rating'
            WHEN category IS NULL OR category = '' THEN 'Missing category'
            WHEN date > GETDATE() THEN 'Future date'
            WHEN date < '2015-01-01' THEN 'Suspicious old date'
            ELSE 'Valid'
        END AS quality_flag
        
    FROM base
)

SELECT 
    -- Surrogate key
    feedback_id AS feedback_key,
    
    -- Identifiers
    feedback_id,
    customer_id_clean AS customer_id,
    
    -- Date attributes
    feedback_date,
    feedback_year,
    feedback_month,
    feedback_quarter,
    feedback_year_month,
    
    -- Feedback content
    rating,
    rating_label,
    sentiment,
    category_clean AS category,
    -- Flags
    CASE 
        WHEN feedback_date > GETDATE() THEN 1 
        ELSE 0 
    END AS is_future_dated,
    -- Quality
    quality_flag,
    
    -- Audit
    GETDATE() AS etl_load_date,
    'silver.feedback' AS etl_source
    
INTO silver.feedback
FROM cleaned
WHERE rating BETWEEN 1 AND 5  -- Only valid ratings
ORDER BY feedback_date DESC, rating DESC
