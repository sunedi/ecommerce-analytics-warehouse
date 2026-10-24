/*
Checks the latest run of the reconciliation controls.

1. The run passed: every measure gives the same value in every layer.
2. The exception register is current. Its open exceptions are recounted here
   independently: an order is an exception unless it reconciles (items and payments
   present, within R$0.01) or has neither items nor payments. That is the opposite
   way round from the procedure's classification, so a mistake in either shows up.
3. The register is internally consistent: statuses, run references and severities.

Returns one row per check, then raises an error if any check failed.
*/
USE EcommerceDW;
GO

SET NOCOUNT ON;

DECLARE @latest_run INT = (SELECT MAX(run_id) FROM audit.control_run);

DROP TABLE IF EXISTS #checks;
CREATE TABLE #checks (
    check_group VARCHAR(20)    NOT NULL,
    check_name  NVARCHAR(200)  NOT NULL,
    expected    DECIMAL(19, 4) NOT NULL,
    actual      DECIMAL(19, 4) NOT NULL,
    result      AS CASE WHEN expected = actual THEN 'PASS' ELSE 'FAIL' END
);

-- Orders that do NOT reconcile, written as the opposite of "reconciles or has nothing to reconcile"
DROP TABLE IF EXISTS #unreconciled;

SELECT order_id, payment_total - (item_total + freight_total) AS difference
INTO #unreconciled
FROM dw.fct_order
WHERE NOT (
        (item_count > 0 AND payment_count > 0 AND ABS(payment_total - (item_total + freight_total)) <= 0.01)
     OR (item_count = 0 AND payment_count = 0)
);

INSERT INTO #checks (check_group, check_name, expected, actual)
SELECT 'control run', 'latest run passed (1 = passed)', 1,
    (SELECT CASE WHEN status = 'passed' THEN 1 ELSE 0 END FROM audit.control_run WHERE run_id = @latest_run)
UNION ALL SELECT 'control run', 'measures checked in the latest run', 6,
    (SELECT measures_checked FROM audit.control_run WHERE run_id = @latest_run)
UNION ALL SELECT 'control run', 'measures whose layers disagree', 0,
    (SELECT measures_failed FROM audit.control_run WHERE run_id = @latest_run)
UNION ALL SELECT 'exceptions', 'open exceptions = orders that do not reconcile',
    (SELECT COUNT(*) FROM #unreconciled),
    (SELECT COUNT(*) FROM audit.payment_exception WHERE status = 'open')
UNION ALL SELECT 'exceptions', 'open exception differences add up',
    (SELECT SUM(difference) FROM #unreconciled),
    (SELECT SUM(difference) FROM audit.payment_exception WHERE status = 'open')
UNION ALL SELECT 'exceptions', 'unreconciled orders missing from the open register', 0,
    (SELECT COUNT(*) FROM #unreconciled AS u
     WHERE NOT EXISTS (SELECT 1 FROM audit.payment_exception AS e WHERE e.order_id = u.order_id AND e.status = 'open'))
UNION ALL SELECT 'register', 'open exceptions not seen in the latest run', 0,
    (SELECT COUNT(*) FROM audit.payment_exception WHERE status = 'open' AND last_detected_run_id <> @latest_run)
UNION ALL SELECT 'register', 'statuses other than open or resolved', 0,
    (SELECT COUNT(*) FROM audit.payment_exception WHERE status NOT IN ('open', 'resolved'))
UNION ALL SELECT 'register', 'resolved exceptions without a resolving run, or open ones with one', 0,
    (SELECT COUNT(*) FROM audit.payment_exception
     WHERE (status = 'resolved' AND resolved_run_id IS NULL) OR (status = 'open' AND resolved_run_id IS NOT NULL))
UNION ALL SELECT 'register', 'severity does not match the amount', 0,
    (SELECT COUNT(*) FROM audit.payment_exception
     WHERE severity <> CASE WHEN ABS(difference) >= 100 THEN 'HIGH' WHEN ABS(difference) >= 10 THEN 'MEDIUM' ELSE 'LOW' END);

SELECT check_group, check_name, expected, actual, result
FROM #checks
ORDER BY CASE result WHEN 'FAIL' THEN 0 ELSE 1 END, check_group, check_name;

IF EXISTS (SELECT 1 FROM #checks WHERE result = 'FAIL')
    THROW 50005, 'Control checks failed. See the results above.', 1;

DECLARE @check_count INT = (SELECT COUNT(*) FROM #checks);
PRINT CONCAT('All ', @check_count, ' control checks passed.');
GO
