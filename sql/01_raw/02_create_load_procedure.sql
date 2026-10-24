/*
raw.usp_load_raw

Loads data/source_manifest.csv into audit.source_manifest, then loads each
Olist CSV file into its raw table without changing any values.

@data_dir is the project's data folder: the one that holds source_manifest.csv
and the raw\ subfolder. Passing it in keeps machine-specific paths out of the code.

Each file is loaded in its own transaction (empty the table, then BULK INSERT),
so rerunning the procedure replaces the data instead of duplicating it, and a
failed file leaves its table as it was before. Every attempt is written to
audit.load_log, and the first failure stops the procedure with the original error.

Example:
    EXEC raw.usp_load_raw @data_dir = N'C:\projects\ecommerce-analytics-warehouse\data';
*/
USE EcommerceDW;
GO

CREATE OR ALTER PROCEDURE raw.usp_load_raw
    @data_dir NVARCHAR(400)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @batch_id INT = (SELECT ISNULL(MAX(batch_id), 0) + 1 FROM audit.load_log);

    -- The reviews and translation files use Windows line endings (CR LF); the others use LF only
    DECLARE @files TABLE (
        load_order     INT           PRIMARY KEY,
        file_name      NVARCHAR(100) NOT NULL,
        target_table   NVARCHAR(128) NOT NULL,
        row_terminator VARCHAR(10)   NOT NULL
    );
    INSERT INTO @files (load_order, file_name, target_table, row_terminator)
    VALUES
        (1, N'olist_customers_dataset.csv',           N'olist_customers',                   '0x0a'),
        (2, N'olist_geolocation_dataset.csv',         N'olist_geolocation',                 '0x0a'),
        (3, N'olist_order_items_dataset.csv',         N'olist_order_items',                 '0x0a'),
        (4, N'olist_order_payments_dataset.csv',      N'olist_order_payments',              '0x0a'),
        (5, N'olist_order_reviews_dataset.csv',       N'olist_order_reviews',               '0x0d0a'),
        (6, N'olist_orders_dataset.csv',              N'olist_orders',                      '0x0a'),
        (7, N'olist_products_dataset.csv',            N'olist_products',                    '0x0a'),
        (8, N'olist_sellers_dataset.csv',             N'olist_sellers',                     '0x0a'),
        (9, N'product_category_name_translation.csv', N'product_category_name_translation', '0x0d0a');

    DECLARE @sql            NVARCHAR(MAX),
            @count_sql      NVARCHAR(400),
            @load_order     INT = 0,
            @file_name      NVARCHAR(100),
            @target_table   NVARCHAR(128),
            @row_terminator VARCHAR(10),
            @file_path      NVARCHAR(600),
            @rows_loaded    BIGINT,
            @started_at     DATETIME2(0);

    -- 1. Expected contents of each file
    SET @file_path = @data_dir + N'\source_manifest.csv';
    SET @sql = N'
        BULK INSERT audit.source_manifest
        FROM ''' + REPLACE(@file_path, N'''', N'''''') + N'''
        WITH (FORMAT = ''CSV'', FIRSTROW = 2, ROWTERMINATOR = ''0x0a'', CODEPAGE = ''65001'');';

    BEGIN TRANSACTION;
        TRUNCATE TABLE audit.source_manifest;
        EXEC sys.sp_executesql @sql;
    COMMIT;

    -- 2. Source files, one at a time in load_order
    WHILE 1 = 1
    BEGIN
        SELECT TOP (1)
            @load_order     = load_order,
            @file_name      = file_name,
            @target_table   = N'raw.' + QUOTENAME(target_table),
            @row_terminator = row_terminator
        FROM @files
        WHERE load_order > @load_order
        ORDER BY load_order;

        IF @@ROWCOUNT = 0 BREAK;

        SET @started_at = SYSDATETIME();
        SET @file_path  = @data_dir + N'\raw\' + @file_name;

        -- BULK INSERT does not accept a variable as the file name, so the statement is built
        -- as text. Doubling any single quote in the path keeps the string literal intact.
        --   FORMAT = 'CSV'     reads quoted values that contain commas or line breaks
        --   FIRSTROW = 2       skips the header row
        --   CODEPAGE = '65001' reads the file as UTF-8, so Portuguese accents survive
        SET @sql = N'
            BULK INSERT ' + @target_table + N'
            FROM ''' + REPLACE(@file_path, N'''', N'''''') + N'''
            WITH (
                FORMAT          = ''CSV'',
                FIRSTROW        = 2,
                FIELDTERMINATOR = '','',
                ROWTERMINATOR   = ''' + @row_terminator + N''',
                CODEPAGE        = ''65001'',
                TABLOCK
            );';

        SET @count_sql = N'SELECT @n = COUNT_BIG(*) FROM ' + @target_table;

        BEGIN TRY
            BEGIN TRANSACTION;
                EXEC (N'TRUNCATE TABLE ' + @target_table);
                EXEC sys.sp_executesql @sql;
                EXEC sys.sp_executesql @count_sql, N'@n BIGINT OUTPUT', @n = @rows_loaded OUTPUT;
            COMMIT;

            INSERT INTO audit.load_log (batch_id, file_name, target_table, status, rows_loaded, started_at, finished_at)
            VALUES (@batch_id, @file_name, @target_table, 'succeeded', @rows_loaded, @started_at, SYSDATETIME());

            PRINT CONCAT(@file_name, ': ', @rows_loaded, ' rows loaded into ', @target_table);
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK;

            -- Logged after the rollback, so the failure record is kept
            INSERT INTO audit.load_log (batch_id, file_name, target_table, status, started_at, finished_at, error_message)
            VALUES (@batch_id, @file_name, @target_table, 'failed', @started_at, SYSDATETIME(), ERROR_MESSAGE());

            THROW;
        END CATCH;
    END;
END;
GO
