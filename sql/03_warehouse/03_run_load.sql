/*
Builds the star schema from staging, then profiles every warehouse column into
audit.column_profile. Run it after the staging load (sql/02_staging/04_run_load.sql).
*/
USE EcommerceDW;
GO

EXEC dw.usp_load_warehouse;
EXEC audit.usp_profile_columns @schema_name = N'dw';
GO
