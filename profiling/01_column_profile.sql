/*
Column profile of every staging table: NULLs, distinct values, smallest and largest value.

audit.column_profile is refreshed by the build (sql/02_staging/04_run_load.sql).
To refresh it by hand: EXEC audit.usp_profile_columns @schema_name = N'stg';
*/
USE EcommerceDW;
GO

SELECT
    table_name,
    column_name,
    data_type,
    row_count,
    null_count,
    CAST(100.0 * null_count / NULLIF(row_count, 0) AS DECIMAL(5, 2)) AS null_pct,
    distinct_count,
    min_value,
    max_value
FROM audit.column_profile
WHERE schema_name = N'stg'
ORDER BY table_name, column_id;

-- Columns with any missing values, most affected first
SELECT
    table_name,
    column_name,
    null_count,
    CAST(100.0 * null_count / NULLIF(row_count, 0) AS DECIMAL(5, 2)) AS null_pct
FROM audit.column_profile
WHERE schema_name = N'stg'
  AND null_count > 0
ORDER BY null_pct DESC;
