/*
Builds the marts from the star schema. Run it after the warehouse load (sql/03_warehouse/03_run_load.sql).
*/
USE EcommerceDW;
GO

EXEC mart.usp_load_marts;
GO
