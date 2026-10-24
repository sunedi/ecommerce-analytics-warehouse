/*
Runs the staging load, then profiles every staging column into audit.column_profile.
Run it after the raw load (sql/01_raw/03_run_load.sql).
*/
USE EcommerceDW;
GO

EXEC stg.usp_load_staging;
EXEC audit.usp_profile_columns @schema_name = N'stg';
GO
