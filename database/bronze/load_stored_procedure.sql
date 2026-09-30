USE [Blue_canopy]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [bronze].[load_bronze_tables]
    @data_root         NVARCHAR(4000) = N'C:\Users\HomePC\Desktop\Blue canopy\raw_datasets\csv_files',
    @truncate_first    BIT            = 1,
    @continue_on_error BIT            = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    IF @@TRANCOUNT <> 0
    BEGIN
        THROW 50001, 'Run bronze.load_bronze_tables outside an existing transaction.', 1;
    END;

    IF @data_root IS NULL OR LTRIM(RTRIM(@data_root)) = N''
    BEGIN
        THROW 50002, '@data_root must be a non-empty path.', 1;
    END;

    SET @data_root = LTRIM(RTRIM(@data_root));
    SET @data_root = REPLACE(@data_root, N'/', N'\');
    IF RIGHT(@data_root, 1) <> N'\'
        SET @data_root += N'\';

    DECLARE @run_id UNIQUEIDENTIFIER = NEWID();

    DECLARE @files TABLE (
        table_schema  SYSNAME        NOT NULL,
        table_name    SYSNAME        NOT NULL,
        relative_path NVARCHAR(500)  NOT NULL
    );

    INSERT INTO @files (table_schema, table_name, relative_path) VALUES
        (N'bronze', N'competitors_raw',              N'competitive_intelligence\competitors_raw.csv'),
        (N'bronze', N'competitor_quarterly_raw',     N'competitive_intelligence\competitor_quarterly_raw.csv'),
        (N'bronze', N'competitor_stores_raw',        N'competitive_intelligence\competitor_stores_raw.csv'),
        (N'bronze', N'crm_raw',                      N'crm\crm_raw.csv'),
        (N'bronze', N'feedback_raw',                 N'customer_service\feedback_raw.csv'),
        (N'bronze', N'service_interactions_raw',     N'customer_service\service_interactions_raw.csv'),
        (N'bronze', N'gl_transactions_raw',          N'finance\gl_transactions_raw.csv'),
        (N'bronze', N'store_daily_financials_raw',   N'finance\store_daily_financials_raw.csv'),
        (N'bronze', N'gis_counties_raw',             N'gis\gis_counties_raw.csv'),
        (N'bronze', N'gis_locations_raw',            N'gis\gis_locations_raw.csv'),
        (N'bronze', N'employee_shifts_raw',          N'hr\employee_shifts_raw.csv'),
        (N'bronze', N'hr_raw',                       N'hr\hr_raw.csv'),
        (N'bronze', N'time_tracking_raw',            N'hr\time_tracking_raw.csv'),
        (N'bronze', N'inventory_movements_raw',      N'inventory\inventory_movements_raw.csv'),
        (N'bronze', N'inventory_snapshots_raw',      N'inventory\inventory_snapshots_raw.csv'),
        (N'bronze', N'loyalty_transactions_raw',     N'loyalty\loyalty_transactions_raw.csv'),
        (N'bronze', N'economic_raw',                 N'macroeconomic\economic_raw.csv'),
        (N'bronze', N'campaigns_raw',                N'marketing\campaigns_raw.csv'),
        (N'bronze', N'promotions_raw',               N'marketing\promotions_raw.csv'),
        (N'bronze', N'promotion_products_raw',       N'marketing\promotion_products_raw.csv'),
        (N'bronze', N'goods_receipts_raw',           N'procurement\goods_receipts_raw.csv'),
        (N'bronze', N'purchase_orders_raw',          N'procurement\purchase_orders_raw.csv'),
        (N'bronze', N'purchase_order_lines_raw',     N'procurement\purchase_order_lines_raw.csv'),
        (N'bronze', N'products_raw',                 N'products\products_raw.csv'),
        (N'bronze', N'ecommerce_orders_raw',         N'sales\ecommerce_orders_raw.csv'),
        (N'bronze', N'ecommerce_order_lines_raw',    N'sales\ecommerce_order_lines_raw.csv'),
        (N'bronze', N'gift_cards_raw',               N'sales\gift_cards_raw.csv'),
        (N'bronze', N'gift_card_transactions_raw',   N'sales\gift_card_transactions_raw.csv'),
        (N'bronze', N'pos_line_items_raw',           N'sales\pos_line_items_raw.csv'),
        (N'bronze', N'pos_transactions_raw',         N'sales\pos_transactions_raw.csv'),
        (N'bronze', N'returns_raw',                  N'sales\returns_raw.csv'),
        (N'bronze', N'stores_raw',                   N'stores\stores_raw.csv'),
        (N'bronze', N'suppliers_raw',                N'suppliers\suppliers_raw.csv');

    DECLARE
        @schema        SYSNAME,
        @table         SYSNAME,
        @relative_path NVARCHAR(500),
        @full_path     NVARCHAR(MAX),
        @escaped_path  NVARCHAR(MAX),
        @sql           NVARCHAR(MAX),
        @row_count     BIGINT,
        @status        NVARCHAR(20),
        @message       NVARCHAR(4000),
        @total_ok      INT = 0,
        @total_error   INT = 0;

    DECLARE file_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT table_schema, table_name, relative_path
        FROM @files
        ORDER BY relative_path;

    OPEN file_cursor;
    FETCH NEXT FROM file_cursor INTO @schema, @table, @relative_path;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @row_count   = NULL;
        SET @message     = NULL;
        SET @full_path   = CONVERT(NVARCHAR(MAX), @data_root) + @relative_path;
        SET @escaped_path = REPLACE(@full_path, N'''', N'''''');

        BEGIN TRY
            BEGIN TRANSACTION;

            ----------------------------------------------------------------
            -- Special-case tables: stage then insert (handles schema drift)
            ----------------------------------------------------------------
            IF @table = N'competitor_quarterly_raw'
            BEGIN
                IF COL_LENGTH(N'bronze.competitor_quarterly_raw', N'competitor_store_id') IS NULL
                    ALTER TABLE bronze.competitor_quarterly_raw ADD competitor_store_id NVARCHAR(255) NULL;

                DROP TABLE IF EXISTS #stage_competitor_quarterly;
                CREATE TABLE #stage_competitor_quarterly (
                    competitor_id        NVARCHAR(MAX) NULL,
                    competitor_store_id  NVARCHAR(MAX) NULL,
                    quarter              NVARCHAR(MAX) NULL,
                    revenue_kes          NVARCHAR(MAX) NULL,
                    market_share_pct     NVARCHAR(MAX) NULL
                );

                SET @sql = N'BULK INSERT #stage_competitor_quarterly FROM ''' + @escaped_path + N'''
WITH (
    FORMAT     = ''CSV'',
    FIRSTROW   = 2,
    FIELDQUOTE = ''"'',
    CODEPAGE   = ''65001'',
    TABLOCK
);';
                EXEC sys.sp_executesql @sql;

                IF @truncate_first = 1
                    TRUNCATE TABLE bronze.competitor_quarterly_raw;

                INSERT INTO bronze.competitor_quarterly_raw
                    (competitor_id, competitor_store_id, quarter, revenue_kes, market_share_pct)
                SELECT competitor_id, competitor_store_id, quarter, revenue_kes, market_share_pct
                FROM #stage_competitor_quarterly;

                DROP TABLE #stage_competitor_quarterly;
            END
            ELSE IF @table = N'gift_card_transactions_raw'
            BEGIN
                IF COL_LENGTH(N'bronze.gift_card_transactions_raw', N'linked_transaction_id') IS NULL
                    ALTER TABLE bronze.gift_card_transactions_raw ADD linked_transaction_id NVARCHAR(255) NULL;

                DROP TABLE IF EXISTS #stage_gift_card_transactions;
                CREATE TABLE #stage_gift_card_transactions (
                    transaction_id        NVARCHAR(MAX) NULL,
                    card_number           NVARCHAR(MAX) NULL,
                    [date]                NVARCHAR(MAX) NULL,
                    amount                NVARCHAR(MAX) NULL,
                    [type]                NVARCHAR(MAX) NULL,
                    linked_transaction_id NVARCHAR(MAX) NULL
                );

                SET @sql = N'BULK INSERT #stage_gift_card_transactions FROM ''' + @escaped_path + N'''
WITH (
    FORMAT     = ''CSV'',
    FIRSTROW   = 2,
    FIELDQUOTE = ''"'',
    CODEPAGE   = ''65001'',
    TABLOCK
);';
                EXEC sys.sp_executesql @sql;

                IF @truncate_first = 1
                    TRUNCATE TABLE bronze.gift_card_transactions_raw;

                INSERT INTO bronze.gift_card_transactions_raw
                    (transaction_id, card_number, [date], amount, [type], linked_transaction_id)
                SELECT transaction_id, card_number, [date], amount, [type], linked_transaction_id
                FROM #stage_gift_card_transactions;

                DROP TABLE #stage_gift_card_transactions;
            END
            ELSE IF @table = N'gift_cards_raw'
            BEGIN
                IF COL_LENGTH(N'bronze.gift_cards_raw', N'customer_id') IS NULL
                    ALTER TABLE bronze.gift_cards_raw ADD customer_id NVARCHAR(255) NULL;
                IF COL_LENGTH(N'bronze.gift_cards_raw', N'transaction_ids') IS NULL
                    ALTER TABLE bronze.gift_cards_raw ADD transaction_ids NVARCHAR(MAX) NULL;

                DROP TABLE IF EXISTS #stage_gift_cards;
                CREATE TABLE #stage_gift_cards (
                    card_number       NVARCHAR(MAX) NULL,
                    customer_id       NVARCHAR(MAX) NULL,
                    issue_date        NVARCHAR(MAX) NULL,
                    expiry_date       NVARCHAR(MAX) NULL,
                    initial_balance   NVARCHAR(MAX) NULL,
                    current_balance   NVARCHAR(MAX) NULL,
                    transaction_ids   NVARCHAR(MAX) NULL    -- widened: no length cap
                );

                SET @sql = N'BULK INSERT #stage_gift_cards FROM ''' + @escaped_path + N'''
WITH (
    FORMAT     = ''CSV'',
    FIRSTROW   = 2,
    FIELDQUOTE = ''"'',
    CODEPAGE   = ''65001'',
    TABLOCK
);';
                EXEC sys.sp_executesql @sql;

                IF @truncate_first = 1
                    TRUNCATE TABLE bronze.gift_cards_raw;

                INSERT INTO bronze.gift_cards_raw
                    (card_number, customer_id, issue_date, expiry_date,
                     initial_balance, current_balance, transaction_ids)
                SELECT card_number, customer_id, issue_date, expiry_date,
                       initial_balance, current_balance, transaction_ids
                FROM #stage_gift_cards;

                DROP TABLE #stage_gift_cards;
            END
            ELSE IF @table = N'pos_line_items_raw'
            BEGIN
                IF COL_LENGTH(N'bronze.pos_line_items_raw', N'discount_source') IS NULL
                    ALTER TABLE bronze.pos_line_items_raw ADD discount_source NVARCHAR(255) NULL;

                DROP TABLE IF EXISTS #stage_pos_line_items;
                CREATE TABLE #stage_pos_line_items (
                    transaction_id   NVARCHAR(MAX) NULL,
                    line_number      NVARCHAR(MAX) NULL,
                    product_id       NVARCHAR(MAX) NULL,
                    quantity         NVARCHAR(MAX) NULL,
                    unit_price       NVARCHAR(MAX) NULL,
                    discount_rate    NVARCHAR(MAX) NULL,
                    discount_source  NVARCHAR(MAX) NULL,
                    line_total       NVARCHAR(MAX) NULL
                );

                SET @sql = N'BULK INSERT #stage_pos_line_items FROM ''' + @escaped_path + N'''
WITH (
    FORMAT     = ''CSV'',
    FIRSTROW   = 2,
    FIELDQUOTE = ''"'',
    CODEPAGE   = ''65001'',
    TABLOCK
);';
                EXEC sys.sp_executesql @sql;

                IF @truncate_first = 1
                    TRUNCATE TABLE bronze.pos_line_items_raw;

                INSERT INTO bronze.pos_line_items_raw
                    (transaction_id, line_number, product_id, quantity, unit_price,
                     discount_rate, discount_source, line_total)
                SELECT transaction_id, line_number, product_id, quantity, unit_price,
                       discount_rate, discount_source, line_total
                FROM #stage_pos_line_items;

                DROP TABLE #stage_pos_line_items;
            END
            ELSE
            BEGIN
                ----------------------------------------------------------------
                -- Generic path: direct BULK INSERT into the bronze table
                ----------------------------------------------------------------
                IF @truncate_first = 1
                BEGIN
                    SET @sql = N'TRUNCATE TABLE ' + QUOTENAME(@schema) + N'.' + QUOTENAME(@table) + N';';
                    EXEC sys.sp_executesql @sql;
                END;

                SET @sql = N'BULK INSERT ' + QUOTENAME(@schema) + N'.' + QUOTENAME(@table)
                    + N' FROM ''' + @escaped_path + N'''
WITH (
    FORMAT     = ''CSV'',
    FIRSTROW   = 2,
    FIELDQUOTE = ''"'',
    CODEPAGE   = ''65001'',
    TABLOCK
);';
                EXEC sys.sp_executesql @sql;
            END;

            ----------------------------------------------------------------
            -- Row count + commit
            ----------------------------------------------------------------
            SET @sql = N'SELECT @row_count_out = COUNT_BIG(*) FROM '
                + QUOTENAME(@schema) + N'.' + QUOTENAME(@table) + N';';
            EXEC sys.sp_executesql
                @sql,
                N'@row_count_out BIGINT OUTPUT',
                @row_count_out = @row_count OUTPUT;

            COMMIT TRANSACTION;

            SET @status    = N'OK';
            SET @total_ok += 1;

            PRINT N'Loaded ' + QUOTENAME(@schema) + N'.' + QUOTENAME(@table)
                + N' (' + CONVERT(NVARCHAR(30), @row_count) + N' rows).';
        END TRY
        BEGIN CATCH
            SET @message = LEFT(
                CONCAT(N'Error ', ERROR_NUMBER(), N': ', ERROR_MESSAGE()),
                4000
            );

            IF XACT_STATE() <> 0
                ROLLBACK TRANSACTION;

            DROP TABLE IF EXISTS #stage_competitor_quarterly;
            DROP TABLE IF EXISTS #stage_gift_card_transactions;
            DROP TABLE IF EXISTS #stage_gift_cards;
            DROP TABLE IF EXISTS #stage_pos_line_items;

            SET @status       = N'ERROR';
            SET @total_error += 1;

            PRINT N'Failed ' + QUOTENAME(@schema) + N'.' + QUOTENAME(@table) + N': ' + @message;
        END CATCH;

        INSERT INTO bronze.load_log (run_id, table_name, status, row_count, message)
        VALUES (@run_id, @schema + N'.' + @table, @status, @row_count, @message);

        IF @status = N'ERROR' AND @continue_on_error = 0
            BREAK;

        FETCH NEXT FROM file_cursor INTO @schema, @table, @relative_path;
    END;

    CLOSE file_cursor;
    DEALLOCATE file_cursor;

    SELECT
        @run_id      AS run_id,
        @total_ok    AS tables_loaded,
        @total_error AS tables_failed;

    SELECT table_name, status, row_count, message, logged_at
    FROM bronze.load_log
    WHERE run_id = @run_id
    ORDER BY table_name;
END;
GO
