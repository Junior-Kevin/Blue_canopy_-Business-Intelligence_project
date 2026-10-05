-- ======================================================
-- Create Database: Blue_canopy
-- ======================================================
CREATE DATABASE Blue_canopy;
GO
USE Blue_canopy;
GO
-- ======================================================
-- Create Schemas
-- ======================================================
CREATE SCHEMA bronze;
GO
CREATE SCHEMA silver;
GO
CREATE SCHEMA gold;
GO

-- ======================================================
-- Optional: Verify creation
-- ======================================================
SELECT name, schema_id, principal_id
FROM sys.schemas
WHERE name IN ('bronze', 'silver', 'gold');
