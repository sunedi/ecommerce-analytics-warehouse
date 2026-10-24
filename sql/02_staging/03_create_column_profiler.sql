/*
audit.usp_profile_columns

Profiles every column of every table in one schema and stores the results in
audit.column_profile: row count, NULL count, number of distinct values, and the
smallest and largest value.

The query for each column is generated from SQL Server's catalog views
(sys.tables, sys.columns), so new tables and columns are profiled automatically.

Example:
    EXEC audit.usp_profile_columns @schema_name = N'stg';
    SELECT * FROM audit.column_profile WHERE schema_name = N'stg';
*/
USE EcommerceDW;
GO

DROP TABLE IF EXISTS audit.column_profile;
CREATE TABLE audit.column_profile (
    schema_name    SYSNAME        NOT NULL,
    table_name     SYSNAME        NOT NULL,
    column_name    SYSNAME        NOT NULL,
    column_id      INT            NOT NULL,  -- position of the column in its table
    data_type      SYSNAME        NOT NULL,
    row_count      BIGINT         NOT NULL,
    null_count     BIGINT         NOT NULL,
    distinct_count BIGINT         NOT NULL,  -- NULL is not counted as a value
    min_value      NVARCHAR(4000) NULL,
    max_value      NVARCHAR(4000) NULL,
    profiled_at    DATETIME2(0)   NOT NULL,
    CONSTRAINT pk_column_profile PRIMARY KEY (schema_name, table_name, column_name)
);
GO

CREATE OR ALTER PROCEDURE audit.usp_profile_columns
    @schema_name SYSNAME
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @sql NVARCHAR(MAX);

    -- Build one INSERT ... SELECT per column and join them into a single batch.
    -- QUOTENAME(name) makes a safe [identifier]; QUOTENAME(name, '''') makes a safe 'string'.
    -- MIN and MAX don't accept BIT (flag) columns, so those are converted to INT first.
    SELECT @sql = STRING_AGG(CAST(N'
        INSERT INTO audit.column_profile
            (schema_name, table_name, column_name, column_id, data_type,
             row_count, null_count, distinct_count, min_value, max_value, profiled_at)
        SELECT '
            + QUOTENAME(s.name, '''') + N', '
            + QUOTENAME(t.name, '''') + N', '
            + QUOTENAME(c.name, '''') + N', '
            + CAST(c.column_id AS NVARCHAR(10)) + N', '
            + QUOTENAME(ty.name, '''') + N',
            COUNT_BIG(*),
            COUNT_BIG(*) - COUNT_BIG(' + QUOTENAME(c.name) + N'),
            COUNT_BIG(DISTINCT ' + QUOTENAME(c.name) + N'),
            CAST(MIN(' + v.min_max_expression + N') AS NVARCHAR(4000)),
            CAST(MAX(' + v.min_max_expression + N') AS NVARCHAR(4000)),
            SYSDATETIME()
        FROM ' + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name) + N';' AS NVARCHAR(MAX)), N'')
        WITHIN GROUP (ORDER BY t.name, c.column_id)
    FROM sys.tables AS t
    INNER JOIN sys.schemas AS s
        ON s.schema_id = t.schema_id
    INNER JOIN sys.columns AS c
        ON c.object_id = t.object_id
    INNER JOIN sys.types AS ty
        ON ty.user_type_id = c.user_type_id
    CROSS APPLY (
        SELECT CASE WHEN ty.name = N'bit' THEN N'CAST(' + QUOTENAME(c.name) + N' AS INT)' ELSE QUOTENAME(c.name) END
    ) AS v (min_max_expression)
    WHERE s.name = @schema_name;

    IF @sql IS NULL
        THROW 50010, 'No tables found in that schema.', 1;

    BEGIN TRANSACTION;
        DELETE FROM audit.column_profile WHERE schema_name = @schema_name;
        EXEC sys.sp_executesql @sql;
    COMMIT;
END;
GO
