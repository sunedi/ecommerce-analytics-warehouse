/*
Runs the raw load.

build.ps1 runs this with sqlcmd, which replaces $(DataDir) with the project's data folder.
To run it in SSMS instead, either replace $(DataDir) with the full path to the data folder,
or turn on Query > SQLCMD Mode and add this line at the top:
    :setvar DataDir "C:\path\to\ecommerce-analytics-warehouse\data"
*/
USE EcommerceDW;
GO

EXEC raw.usp_load_raw @data_dir = N'$(DataDir)';
GO
