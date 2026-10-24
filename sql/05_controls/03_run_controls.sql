/*
Runs the reconciliation controls. Run it after the marts are built (sql/04_marts/03_run_load.sql).
*/
USE EcommerceDW;
GO

EXEC audit.usp_run_controls;
GO
