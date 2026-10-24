/*
Audit tables used to prove that each load is complete.

audit.source_manifest  what each source file should contain, loaded from data/source_manifest.csv
audit.load_log         one row per file per load attempt, kept across rebuilds
*/
USE EcommerceDW;
GO

-- Reloaded from data/source_manifest.csv on every load
IF OBJECT_ID(N'audit.source_manifest', N'U') IS NULL
    CREATE TABLE audit.source_manifest (
        file_name    NVARCHAR(100) NOT NULL PRIMARY KEY,
        size_bytes   BIGINT        NOT NULL,
        sha256       CHAR(64)      NOT NULL,
        record_count INT           NOT NULL  -- data records, excluding the header row
    );
GO

-- Created only if missing, so the history of earlier loads survives a rebuild
IF OBJECT_ID(N'audit.load_log', N'U') IS NULL
    CREATE TABLE audit.load_log (
        load_id       INT IDENTITY(1, 1) PRIMARY KEY,
        batch_id      INT            NOT NULL,  -- all files loaded by one run of raw.usp_load_raw
        file_name     NVARCHAR(100)  NOT NULL,
        target_table  NVARCHAR(128)  NOT NULL,
        status        VARCHAR(10)    NOT NULL,  -- 'succeeded' or 'failed'
        rows_loaded   BIGINT         NULL,
        started_at    DATETIME2(0)   NOT NULL,
        finished_at   DATETIME2(0)   NOT NULL,
        error_message NVARCHAR(4000) NULL
    );
GO
