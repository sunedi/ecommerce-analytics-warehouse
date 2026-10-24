/*
Control tables: an auditable record of every reconciliation run.

audit.control_run        one row per run of audit.usp_run_controls
audit.control_total      the same measure (e.g. total item price) taken from every layer,
                         from the source file through to the marts, for every run
audit.payment_exception  a register of orders whose payments don't reconcile, with a
                         reason code and severity. Each exception is opened the first time
                         it is detected and closed (resolved) when it no longer appears.

The tests in tests/ stop a build that is wrong. These tables keep the evidence: they
show what was checked, when, and what was found, run after run.

All three are created only if missing, so their history survives a rebuild.
*/
USE EcommerceDW;
GO

IF OBJECT_ID(N'audit.control_run', N'U') IS NULL
    CREATE TABLE audit.control_run (
        run_id                 INT IDENTITY(1, 1) NOT NULL,
        started_at             DATETIME2(0)       NOT NULL,
        finished_at            DATETIME2(0)       NULL,
        status                 VARCHAR(10)        NOT NULL,  -- running, passed, failed, error
        measures_checked       INT                NULL,
        measures_failed        INT                NULL,      -- measures whose layers disagree
        open_exceptions        INT                NULL,
        new_exceptions         INT                NULL,
        resolved_exceptions    INT                NULL,
        open_exception_amount  DECIMAL(14, 2)     NULL,      -- sum of ABS(difference) of open exceptions
        error_message          NVARCHAR(4000)     NULL,
        CONSTRAINT pk_control_run PRIMARY KEY (run_id)
    );
GO

IF OBJECT_ID(N'audit.control_total', N'U') IS NULL
    CREATE TABLE audit.control_total (
        run_id   INT            NOT NULL,
        measure  VARCHAR(50)    NOT NULL,
        layer    VARCHAR(50)    NOT NULL,
        value    DECIMAL(19, 4) NULL,
        CONSTRAINT pk_control_total PRIMARY KEY (run_id, measure, layer),
        CONSTRAINT fk_control_total_run FOREIGN KEY (run_id) REFERENCES audit.control_run (run_id)
    );
GO

IF OBJECT_ID(N'audit.payment_exception', N'U') IS NULL
    CREATE TABLE audit.payment_exception (
        order_id              CHAR(32)       NOT NULL,
        reason_code           VARCHAR(20)    NOT NULL,  -- PAID_NO_ITEMS, NO_PAYMENT, OVERPAID, UNDERPAID
        severity              VARCHAR(10)    NOT NULL,  -- HIGH (R$100+), MEDIUM (R$10+), LOW
        order_status          VARCHAR(20)    NOT NULL,
        amount_due            DECIMAL(12, 2) NOT NULL,  -- item prices + freight
        amount_paid           DECIMAL(12, 2) NOT NULL,
        difference            DECIMAL(12, 2) NOT NULL,  -- paid minus due
        status                VARCHAR(10)    NOT NULL,  -- open or resolved
        first_detected_run_id INT            NOT NULL,
        last_detected_run_id  INT            NOT NULL,
        resolved_run_id       INT            NULL,
        CONSTRAINT pk_payment_exception PRIMARY KEY (order_id),
        CONSTRAINT fk_payment_exception_first FOREIGN KEY (first_detected_run_id) REFERENCES audit.control_run (run_id),
        CONSTRAINT fk_payment_exception_last  FOREIGN KEY (last_detected_run_id)  REFERENCES audit.control_run (run_id)
    );
GO
