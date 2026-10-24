/*
Creates one schema per layer, so every table name shows which layer it belongs to.

    raw    source CSV files loaded exactly as they are (every column is text)
    stg    cleaned, typed and renamed copies of the raw tables
    dw     star schema: dimensions and facts
    mart   summary tables for reporting and analysis
    audit  load history and the expected contents of each source file
*/
USE EcommerceDW;
GO

-- CREATE SCHEMA has to be the only statement in its batch, so it is run through EXEC
IF SCHEMA_ID(N'raw')   IS NULL EXEC (N'CREATE SCHEMA raw');
IF SCHEMA_ID(N'stg')   IS NULL EXEC (N'CREATE SCHEMA stg');
IF SCHEMA_ID(N'dw')    IS NULL EXEC (N'CREATE SCHEMA dw');
IF SCHEMA_ID(N'mart')  IS NULL EXEC (N'CREATE SCHEMA mart');
IF SCHEMA_ID(N'audit') IS NULL EXEC (N'CREATE SCHEMA audit');
GO
