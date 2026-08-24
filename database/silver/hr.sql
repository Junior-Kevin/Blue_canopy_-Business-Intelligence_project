-- Drop table if exists
IF OBJECT_ID('[Blue_canopy].[silver].[hr]', 'U') IS NOT NULL
    DROP TABLE [Blue_canopy].[silver].[hr];

-- SELECT INTO creates the table automatically
WITH DateCleaned AS (
    SELECT 
        [employee_id],
        [first_name],
        [last_name],
        [gender],
        [department],
        [job_title],
        [salary],
        [store_id],
        [shift_pattern],
        
        -- Safe date conversion using TRY_CAST
        TRY_CAST(
            CASE 
                WHEN valid_from = '2023-13-45' THEN NULL
                WHEN valid_from LIKE '%[^0-9-]%' THEN NULL
                ELSE valid_from 
            END AS DATE
        ) AS valid_from,
        
        TRY_CAST(
            CASE 
                WHEN valid_to = '2023-13-45' THEN NULL
                WHEN valid_to LIKE '%[^0-9-]%' THEN NULL
                ELSE valid_to 
            END AS DATE
        ) AS valid_to,
        
        TRY_CAST(
            CASE 
                WHEN birth_date = '2023-13-45' THEN NULL
                WHEN birth_date LIKE '%[^0-9-]%' THEN NULL
                ELSE birth_date 
            END AS DATE
        ) AS birth_date,
        
        TRY_CAST(
            CASE 
                WHEN hire_date = '2023-13-45' THEN NULL
                WHEN hire_date LIKE '%[^0-9-]%' THEN NULL
                ELSE hire_date 
            END AS DATE
        ) AS hire_date,
        
        -- Safe salary conversion
        TRY_CAST([salary] AS INT) AS salary_clean
        
    FROM [Blue_canopy].[bronze].[hr_raw]
    WHERE employee_id NOT LIKE '%DUP'
),
EducationData AS (
    SELECT 
        *,
        CASE 
            WHEN [job_title] IN ('Store Manager', 'Finance Manager', 'Warehouse Manager', 
                                  'Supply Chain Manager', 'IT Manager', 'HR Manager') 
                 THEN CASE ABS(CHECKSUM(NEWID())) % 3
                          WHEN 0 THEN 'Bachelor''s Degree'
                          WHEN 1 THEN 'Master''s Degree'
                          ELSE 'MBA'
                      END
            WHEN [job_title] IN ('Marketing Manager', 'Brand Officer', 'Recruiter', 
                                  'Accountant', 'Senior Sales', 'Procurement Officer', 
                                  'Logistics Officer', 'Customer Care', 'Digital Officer',
                                  'Auditor', 'Systems Admin', 'HR Officer')
                 THEN 'Bachelor''s Degree'
            WHEN [job_title] IN ('Developer', 'Systems Admin', 'Auditor')
                 THEN CASE ABS(CHECKSUM(NEWID())) % 2
                          WHEN 0 THEN 'Bachelor''s Degree'
                          ELSE 'Associate Degree'
                      END
            WHEN [job_title] IN ('Supervisor', 'Assistant Manager')
                 THEN CASE ABS(CHECKSUM(NEWID())) % 3
                          WHEN 0 THEN 'Bachelor''s Degree'
                          WHEN 1 THEN 'Master''s Degree'
                          ELSE 'Associate Degree'
                      END
            WHEN [job_title] IN ('Cashier', 'Sales Associate', 'Stock Keeper', 
                                  'Loader', 'Forklift Operator', 'Security', 
                                  'Support', 'Promoter')
                 THEN CASE ABS(CHECKSUM(NEWID())) % 3
                          WHEN 0 THEN 'High School Diploma'
                          WHEN 1 THEN 'Some College'
                          ELSE 'Associate Degree'
                      END
            WHEN [job_title] IS NULL
                 THEN CASE ABS(CHECKSUM(NEWID())) % 5
                          WHEN 0 THEN 'High School Diploma'
                          WHEN 1 THEN 'Some College'
                          WHEN 2 THEN 'Associate Degree'
                          WHEN 3 THEN 'Bachelor''s Degree'
                          ELSE 'Master''s Degree'
                      END
            ELSE CASE ABS(CHECKSUM(NEWID())) % 4
                      WHEN 0 THEN 'High School Diploma'
                      WHEN 1 THEN 'Some College'
                      WHEN 2 THEN 'Associate Degree'
                      ELSE 'Bachelor''s Degree'
                 END
        END AS education_level
    FROM DateCleaned
)
SELECT 
    -- Core Identifiers
    [employee_id],
    [first_name],
    [last_name],
    [gender],
    [department],
    [job_title],
    [store_id],
    [shift_pattern],
    
    -- Dates (with NULL handling)
    valid_from,
    valid_to,
    birth_date,
    hire_date,
    
    -- Clean salary
    COALESCE(salary_clean, 0) AS salary,
    
    -- Education Level
    education_level,
    
    -- Age Analytics (with NULL check)
    CASE 
        WHEN birth_date IS NOT NULL THEN DATEDIFF(YEAR, birth_date, GETDATE())
        ELSE NULL 
    END AS age,
    
    CASE 
        WHEN birth_date IS NULL THEN 'Unknown'
        WHEN DATEDIFF(YEAR, birth_date, GETDATE()) < 25 THEN 'Gen Z (18-24)'
        WHEN DATEDIFF(YEAR, birth_date, GETDATE()) < 35 THEN 'Young Millennial (25-34)'
        WHEN DATEDIFF(YEAR, birth_date, GETDATE()) < 45 THEN 'Senior Millennial (35-44)'
        WHEN DATEDIFF(YEAR, birth_date, GETDATE()) < 55 THEN 'Gen X (45-54)'
        ELSE 'Boomer+ (55+)'
    END AS generation,
    
    -- Full Name & Name Components
    CONCAT(COALESCE(first_name, ''), ' ', COALESCE(last_name, '')) AS full_name,
    LEFT(COALESCE(first_name, 'N'), 1) + '. ' + COALESCE(last_name, 'Unknown') AS display_name,
    
    -- Email Generation
    LOWER(CONCAT(COALESCE(first_name, 'unknown'), '.', COALESCE(last_name, 'unknown'), '@company.com')) AS generated_email,
    
    -- Tenure Calculations (with NULL check)
    CASE WHEN hire_date IS NOT NULL THEN DATEDIFF(DAY, hire_date, GETDATE()) ELSE NULL END AS tenure_days,
    CASE WHEN hire_date IS NOT NULL THEN DATEDIFF(MONTH, hire_date, GETDATE()) ELSE NULL END AS tenure_months,
    CASE WHEN hire_date IS NOT NULL THEN DATEDIFF(YEAR, hire_date, GETDATE()) ELSE NULL END AS tenure_years,
    
    -- Tenure Bands
    CASE 
        WHEN hire_date IS NULL THEN 'Unknown'
        WHEN DATEDIFF(YEAR, hire_date, GETDATE()) < 1 THEN 'Probation (<1 year)'
        WHEN DATEDIFF(YEAR, hire_date, GETDATE()) < 3 THEN 'Junior (1-3 years)'
        WHEN DATEDIFF(YEAR, hire_date, GETDATE()) < 5 THEN 'Mid (3-5 years)'
        WHEN DATEDIFF(YEAR, hire_date, GETDATE()) < 10 THEN 'Senior (5-10 years)'
        ELSE 'Veteran (10+ years)'
    END AS tenure_band,
    
    -- Retention Risk
    CASE 
        WHEN hire_date IS NULL THEN 'Unknown'
        WHEN DATEDIFF(YEAR, hire_date, GETDATE()) BETWEEN 1 AND 2 THEN 'High Risk'
        WHEN DATEDIFF(YEAR, hire_date, GETDATE()) > 10 THEN 'Low Risk'
        ELSE 'Medium Risk'
    END AS retention_risk,
    
    -- Employment Status
    CASE 
        WHEN valid_to IS NULL THEN 'Active'
        WHEN valid_to > GETDATE() THEN 'Active'
        ELSE 'Inactive/Terminated'
    END AS employment_status,
    
    -- Contract Analysis (with NULL check)
    CASE 
        WHEN valid_from IS NULL THEN NULL
        ELSE DATEDIFF(MONTH, valid_from, COALESCE(valid_to, GETDATE()))
    END AS contract_length_months,
    
    CASE 
        WHEN valid_from IS NULL THEN 'Unknown'
        WHEN DATEDIFF(MONTH, valid_from, COALESCE(valid_to, GETDATE())) <= 12 THEN 'Short-term Contract'
        WHEN DATEDIFF(MONTH, valid_from, COALESCE(valid_to, GETDATE())) <= 24 THEN 'Medium-term Contract'
        WHEN valid_to IS NULL THEN 'Permanent'
        ELSE 'Long-term Contract'
    END AS contract_type,
    
    -- Salary Bands
    CASE 
        WHEN salary_clean < 30000 THEN 'Entry Level (<30K)'
        WHEN salary_clean < 45000 THEN 'Junior (30-45K)'
        WHEN salary_clean < 60000 THEN 'Mid (45-60K)'
        WHEN salary_clean < 80000 THEN 'Senior (60-80K)'
        WHEN salary_clean < 100000 THEN 'Lead (80-100K)'
        ELSE 'Executive (100K+)'
    END AS salary_band,
    
    -- Salary Equity Flag (with NULL check)
    CASE 
        WHEN hire_date IS NULL OR salary_clean IS NULL THEN 'Unknown'
        WHEN salary_clean < 30000 AND DATEDIFF(YEAR, hire_date, GETDATE()) > 5 THEN 'Underpaid'
        WHEN salary_clean > 80000 AND DATEDIFF(YEAR, hire_date, GETDATE()) < 2 THEN 'Overpaid'
        ELSE 'Market Rate'
    END AS salary_equity_flag,
    
    -- Department Groupings
    CASE 
        WHEN department IN ('Sales', 'Marketing', 'Brand') THEN 'Revenue'
        WHEN department IN ('HR', 'Finance', 'IT', 'Legal') THEN 'Corporate'
        WHEN department IN ('Warehouse', 'Logistics', 'Operations') THEN 'Operations'
        WHEN department IN ('Customer Care', 'Support') THEN 'Customer Service'
        ELSE COALESCE(department, 'Other')
    END AS department_category,
    
    -- Job Level Inference
    CASE 
        WHEN job_title LIKE '%Manager%' OR job_title LIKE '%Director%' THEN 'Management'
        WHEN job_title LIKE '%Senior%' OR job_title LIKE '%Lead%' THEN 'Senior'
        WHEN job_title LIKE '%Assistant%' OR job_title LIKE '%Junior%' THEN 'Junior'
        WHEN job_title LIKE '%Intern%' THEN 'Intern'
        ELSE COALESCE(job_title, 'Staff')
    END AS job_level,
    
    -- Management Flag
    CASE 
        WHEN job_title LIKE '%Manager%' OR job_title LIKE '%Director%' 
             OR job_title LIKE '%Supervisor%' OR job_title LIKE '%Lead%' 
        THEN 1 ELSE 0 
    END AS is_manager,
    
    -- Hire Seasonality (with NULL check)
    CASE WHEN hire_date IS NOT NULL THEN DATEPART(MONTH, hire_date) ELSE NULL END AS hire_month,
    CASE WHEN hire_date IS NOT NULL THEN DATEPART(QUARTER, hire_date) ELSE NULL END AS hire_quarter,
    CASE 
        WHEN hire_date IS NULL THEN 'Unknown'
        WHEN DATEPART(MONTH, hire_date) IN (12, 1, 2) THEN 'Winter'
        WHEN DATEPART(MONTH, hire_date) IN (3, 4, 5) THEN 'Spring'
        WHEN DATEPART(MONTH, hire_date) IN (6, 7, 8) THEN 'Summer'
        ELSE 'Fall'
    END AS hire_season,
    
    -- Hire Year Analysis
    CASE WHEN hire_date IS NOT NULL THEN YEAR(hire_date) ELSE NULL END AS hire_year,
    CASE WHEN hire_date IS NOT NULL THEN YEAR(GETDATE()) - YEAR(hire_date) ELSE NULL END AS years_since_hire,
    
    -- Cohort Creation
    CASE 
        WHEN hire_date IS NULL THEN 'Unknown'
        ELSE CONCAT(YEAR(hire_date), '-', 
            CASE 
                WHEN DATEPART(MONTH, hire_date) <= 3 THEN 'Q1'
                WHEN DATEPART(MONTH, hire_date) <= 6 THEN 'Q2'
                WHEN DATEPART(MONTH, hire_date) <= 9 THEN 'Q3'
                ELSE 'Q4'
            END)
    END AS hire_cohort,
    
    -- Gender Balance
    CASE 
        WHEN gender IN ('Male', 'M') THEN 'Male'
        WHEN gender IN ('Female', 'F') THEN 'Female'
        ELSE 'Other/Not Specified'
    END AS gender_category,
    
    -- Age Band
    CASE 
        WHEN birth_date IS NULL THEN 'Unknown'
        WHEN DATEDIFF(YEAR, birth_date, GETDATE()) < 30 THEN 'Under 30'
        WHEN DATEDIFF(YEAR, birth_date, GETDATE()) < 40 THEN '30-39'
        WHEN DATEDIFF(YEAR, birth_date, GETDATE()) < 50 THEN '40-49'
        ELSE '50+'
    END AS age_band
    
INTO [Blue_canopy].[silver].[hr]
FROM EducationData;
