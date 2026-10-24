/*
audit.usp_run_controls

Runs the reconciliation controls and records the results:

1. Control totals. Each measure is taken from every layer it passes through, from
   the source file manifest to the marts. A measure passes when every layer gives
   the same value. Any difference means data was lost, repeated or changed on the way.

2. Payment exceptions. Every order whose payments don't match its items plus freight
   (to within R$0.01) is given a reason code and severity, and the register in
   audit.payment_exception is brought up to date with MERGE:
     - an exception seen for the first time is opened,
     - an exception seen again keeps its first-detected run and is updated,
     - an open exception that has disappeared is marked resolved.
   Rerunning the controls on unchanged data therefore changes nothing: no duplicates,
   nothing new, nothing resolved.

The run is recorded in audit.control_run as passed or failed. The procedure doesn't
stop on a failed control; tests/05_control_checks.sql does that.

Example:
    EXEC audit.usp_run_controls;
    SELECT TOP (1) * FROM audit.control_run ORDER BY run_id DESC;
*/
USE EcommerceDW;
GO

CREATE OR ALTER PROCEDURE audit.usp_run_controls
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- The run is recorded before the work starts, so a run that crashes still leaves a trace
    INSERT INTO audit.control_run (started_at, status) VALUES (SYSDATETIME(), 'running');
    DECLARE @run_id INT = SCOPE_IDENTITY();

    BEGIN TRY
        BEGIN TRANSACTION;

        /* -----------------------------------------------------------------
           1. Control totals: one row per measure per layer
           ----------------------------------------------------------------- */
        INSERT INTO audit.control_total (run_id, measure, layer, value)
        SELECT @run_id, measure, layer, value
        FROM (
            SELECT 'item count' AS measure, '1 source file' AS layer,
                   (SELECT record_count FROM audit.source_manifest WHERE file_name = N'olist_order_items_dataset.csv') AS value
            UNION ALL SELECT 'item count', '2 raw',               (SELECT COUNT(*) FROM raw.olist_order_items)
            UNION ALL SELECT 'item count', '3 stg',               (SELECT COUNT(*) FROM stg.order_items)
            UNION ALL SELECT 'item count', '4 dw.fct_order_item', (SELECT COUNT(*) FROM dw.fct_order_item)
            UNION ALL SELECT 'item count', '5 dw.fct_order',      (SELECT SUM(item_count) FROM dw.fct_order)

            UNION ALL SELECT 'order count', '1 source file',
                   (SELECT record_count FROM audit.source_manifest WHERE file_name = N'olist_orders_dataset.csv')
            UNION ALL SELECT 'order count', '2 raw',                       (SELECT COUNT(*) FROM raw.olist_orders)
            UNION ALL SELECT 'order count', '3 stg',                       (SELECT COUNT(*) FROM stg.orders)
            UNION ALL SELECT 'order count', '4 dw.fct_order',              (SELECT COUNT(*) FROM dw.fct_order)
            UNION ALL SELECT 'order count', '6 mart.monthly_performance',  (SELECT SUM(orders) FROM mart.monthly_performance)
            UNION ALL SELECT 'order count', '6 mart.customer_summary',     (SELECT SUM(orders) FROM mart.customer_summary)

            UNION ALL SELECT 'item price total', '2 raw',               (SELECT SUM(TRY_CONVERT(DECIMAL(18, 4), price)) FROM raw.olist_order_items)
            UNION ALL SELECT 'item price total', '3 stg',               (SELECT SUM(price) FROM stg.order_items)
            UNION ALL SELECT 'item price total', '4 dw.fct_order_item', (SELECT SUM(price) FROM dw.fct_order_item)
            UNION ALL SELECT 'item price total', '5 dw.fct_order',      (SELECT SUM(item_total) FROM dw.fct_order)

            UNION ALL SELECT 'freight total', '2 raw',               (SELECT SUM(TRY_CONVERT(DECIMAL(18, 4), freight_value)) FROM raw.olist_order_items)
            UNION ALL SELECT 'freight total', '3 stg',               (SELECT SUM(freight_value) FROM stg.order_items)
            UNION ALL SELECT 'freight total', '4 dw.fct_order_item', (SELECT SUM(freight_value) FROM dw.fct_order_item)
            UNION ALL SELECT 'freight total', '5 dw.fct_order',      (SELECT SUM(freight_total) FROM dw.fct_order)

            UNION ALL SELECT 'payment total', '2 raw',            (SELECT SUM(TRY_CONVERT(DECIMAL(18, 4), payment_value)) FROM raw.olist_order_payments)
            UNION ALL SELECT 'payment total', '3 stg',            (SELECT SUM(payment_value) FROM stg.order_payments)
            UNION ALL SELECT 'payment total', '4 dw.fct_payment', (SELECT SUM(payment_value) FROM dw.fct_payment)
            UNION ALL SELECT 'payment total', '5 dw.fct_order',   (SELECT SUM(payment_total) FROM dw.fct_order)

            UNION ALL SELECT 'delivered revenue', '4 dw.fct_order_item',         (SELECT SUM(price) FROM dw.fct_order_item WHERE is_revenue = 1)
            UNION ALL SELECT 'delivered revenue', '5 dw.fct_order',              (SELECT SUM(item_total) FROM dw.fct_order WHERE is_revenue = 1)
            UNION ALL SELECT 'delivered revenue', '6 mart.monthly_performance',  (SELECT SUM(revenue) FROM mart.monthly_performance)
            UNION ALL SELECT 'delivered revenue', '6 mart.state_monthly',        (SELECT SUM(revenue) FROM mart.state_monthly)
            UNION ALL SELECT 'delivered revenue', '6 mart.category_monthly',     (SELECT SUM(revenue) FROM mart.category_monthly)
            UNION ALL SELECT 'delivered revenue', '6 mart.seller_performance',   (SELECT SUM(revenue) FROM mart.seller_performance)
            UNION ALL SELECT 'delivered revenue', '6 mart.customer_summary',     (SELECT SUM(revenue) FROM mart.customer_summary)
        ) AS totals (measure, layer, value);

        -- A measure fails if its layers disagree, or if any layer returned NULL (an empty table)
        DECLARE @measures_checked INT, @measures_failed INT;

        SELECT
            @measures_checked = COUNT(*),
            @measures_failed  = SUM(CASE WHEN lowest_value <> highest_value OR null_values > 0 THEN 1 ELSE 0 END)
        FROM (
            SELECT measure, MIN(value) AS lowest_value, MAX(value) AS highest_value,
                   SUM(CASE WHEN value IS NULL THEN 1 ELSE 0 END) AS null_values
            FROM audit.control_total
            WHERE run_id = @run_id
            GROUP BY measure
        ) AS per_measure;

        /* -----------------------------------------------------------------
           2. Payment exceptions found in this run
           ----------------------------------------------------------------- */
        DROP TABLE IF EXISTS #current_exceptions;

        SELECT
            order_id,
            reason_code,
            CASE
                WHEN ABS(difference) >= 100 THEN 'HIGH'
                WHEN ABS(difference) >= 10  THEN 'MEDIUM'
                ELSE                             'LOW'
            END AS severity,
            order_status,
            amount_due,
            amount_paid,
            difference
        INTO #current_exceptions
        FROM (
            SELECT
                order_id,
                order_status,
                item_total + freight_total                     AS amount_due,
                payment_total                                  AS amount_paid,
                payment_total - (item_total + freight_total)   AS difference,
                -- The order of these tests matters: missing items or payments are classified first
                CASE
                    WHEN item_count = 0 AND payment_count > 0                       THEN 'PAID_NO_ITEMS'
                    WHEN item_count > 0 AND payment_count = 0                       THEN 'NO_PAYMENT'
                    WHEN payment_total - (item_total + freight_total) >  0.01       THEN 'OVERPAID'
                    WHEN payment_total - (item_total + freight_total) < -0.01       THEN 'UNDERPAID'
                END AS reason_code
            FROM dw.fct_order
        ) AS classified
        WHERE reason_code IS NOT NULL;

        /* -----------------------------------------------------------------
           3. Bring the register up to date. OUTPUT records what MERGE did to
              each row, so the run can report new and resolved exceptions.
              HOLDLOCK stops another session changing the register mid-MERGE.
           ----------------------------------------------------------------- */
        DECLARE @changes TABLE (action NVARCHAR(10), old_status VARCHAR(10), new_status VARCHAR(10));

        MERGE audit.payment_exception WITH (HOLDLOCK) AS target
        USING #current_exceptions AS source
            ON target.order_id = source.order_id
        WHEN MATCHED THEN
            UPDATE SET
                reason_code          = source.reason_code,
                severity             = source.severity,
                order_status         = source.order_status,
                amount_due           = source.amount_due,
                amount_paid          = source.amount_paid,
                difference           = source.difference,
                status               = 'open',
                last_detected_run_id = @run_id,
                resolved_run_id      = NULL
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (order_id, reason_code, severity, order_status, amount_due, amount_paid, difference,
                    status, first_detected_run_id, last_detected_run_id, resolved_run_id)
            VALUES (source.order_id, source.reason_code, source.severity, source.order_status, source.amount_due,
                    source.amount_paid, source.difference, 'open', @run_id, @run_id, NULL)
        WHEN NOT MATCHED BY SOURCE AND target.status = 'open' THEN
            UPDATE SET
                status          = 'resolved',
                resolved_run_id = @run_id
        OUTPUT $action, deleted.status, inserted.status INTO @changes (action, old_status, new_status);

        /* -----------------------------------------------------------------
           4. Record the outcome of the run
           ----------------------------------------------------------------- */
        UPDATE audit.control_run
        SET finished_at           = SYSDATETIME(),
            status                = CASE WHEN @measures_failed = 0 THEN 'passed' ELSE 'failed' END,
            measures_checked      = @measures_checked,
            measures_failed       = @measures_failed,
            open_exceptions       = (SELECT COUNT(*) FROM audit.payment_exception WHERE status = 'open'),
            new_exceptions        = (SELECT COUNT(*) FROM @changes WHERE action = 'INSERT'),
            resolved_exceptions   = (SELECT COUNT(*) FROM @changes WHERE old_status = 'open' AND new_status = 'resolved'),
            open_exception_amount = (SELECT SUM(ABS(difference)) FROM audit.payment_exception WHERE status = 'open')
        WHERE run_id = @run_id;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        UPDATE audit.control_run
        SET finished_at = SYSDATETIME(), status = 'error', error_message = ERROR_MESSAGE()
        WHERE run_id = @run_id;

        THROW;
    END CATCH;

    SELECT run_id, status, measures_checked, measures_failed, open_exceptions, new_exceptions,
           resolved_exceptions, open_exception_amount
    FROM audit.control_run
    WHERE run_id = @run_id;
END;
GO
