/*
Checks that every mart reconciles to the star schema.

A dashboard is only as trustworthy as the tables behind it. Each check compares a
mart total with the same total calculated directly from dw. A mismatch means a join
in the mart dropped or repeated rows, or a filter differs from the agreed definition.

Returns one row per check, then raises an error if any check failed.
*/
USE EcommerceDW;
GO

SET NOCOUNT ON;

DROP TABLE IF EXISTS #checks;
CREATE TABLE #checks (
    check_group VARCHAR(25)    NOT NULL,
    check_name  NVARCHAR(200)  NOT NULL,
    expected    DECIMAL(19, 4) NOT NULL,
    actual      DECIMAL(19, 4) NOT NULL,
    result      AS CASE WHEN expected = actual THEN 'PASS' ELSE 'FAIL' END
);

-- Warehouse totals that the marts must reproduce
DECLARE @delivered_revenue DECIMAL(19, 4) = (SELECT SUM(price) FROM dw.fct_order_item WHERE is_revenue = 1);
DECLARE @delivered_freight DECIMAL(19, 4) = (SELECT SUM(freight_total) FROM dw.fct_order WHERE is_revenue = 1);
DECLARE @delivered_items   INT = (SELECT COUNT(*) FROM dw.fct_order_item WHERE is_revenue = 1);
DECLARE @all_orders        INT = (SELECT COUNT(*) FROM dw.fct_order);
DECLARE @delivered_orders  INT = (SELECT COUNT(*) FROM dw.fct_order WHERE is_revenue = 1);
DECLARE @customers         INT = (SELECT COUNT(DISTINCT customer_unique_id) FROM dw.dim_customer);
DECLARE @buying_customers  INT = (
    SELECT COUNT(DISTINCT c.customer_unique_id)
    FROM dw.fct_order AS o
    INNER JOIN dw.dim_customer AS c ON c.customer_key = o.customer_key
    WHERE o.is_revenue = 1
);
DECLARE @repeat_customers  INT = (
    SELECT COUNT(*) FROM (
        SELECT c.customer_unique_id
        FROM dw.fct_order AS o
        INNER JOIN dw.dim_customer AS c ON c.customer_key = o.customer_key
        WHERE o.is_revenue = 1
        GROUP BY c.customer_unique_id
        HAVING COUNT(*) >= 2
    ) AS r
);

INSERT INTO #checks (check_group, check_name, expected, actual)
SELECT 'monthly_performance', 'revenue',          @delivered_revenue, (SELECT SUM(revenue) FROM mart.monthly_performance)
UNION ALL SELECT 'monthly_performance', 'freight',          @delivered_freight, (SELECT SUM(freight) FROM mart.monthly_performance)
UNION ALL SELECT 'monthly_performance', 'orders',           @all_orders,        (SELECT SUM(orders) FROM mart.monthly_performance)
UNION ALL SELECT 'monthly_performance', 'delivered orders', @delivered_orders,  (SELECT SUM(delivered_orders) FROM mart.monthly_performance)
UNION ALL SELECT 'monthly_performance', 'new customers add up to all buying customers', @buying_customers, (SELECT SUM(new_customers) FROM mart.monthly_performance)
UNION ALL SELECT 'state_monthly', 'revenue',          @delivered_revenue, (SELECT SUM(revenue) FROM mart.state_monthly)
UNION ALL SELECT 'state_monthly', 'delivered orders', @delivered_orders,  (SELECT SUM(delivered_orders) FROM mart.state_monthly)
UNION ALL SELECT 'category_monthly', 'revenue',       @delivered_revenue, (SELECT SUM(revenue) FROM mart.category_monthly)
UNION ALL SELECT 'category_monthly', 'items',         @delivered_items,   (SELECT SUM(items) FROM mart.category_monthly)
UNION ALL SELECT 'seller_performance', 'revenue',     @delivered_revenue, (SELECT SUM(revenue) FROM mart.seller_performance)
UNION ALL SELECT 'seller_performance', 'items sold',  @delivered_items,   (SELECT SUM(items_sold) FROM mart.seller_performance)
UNION ALL SELECT 'seller_performance', 'one row per seller', (SELECT COUNT(*) FROM dw.dim_seller), (SELECT COUNT(*) FROM mart.seller_performance)
UNION ALL SELECT 'customer_summary', 'one row per customer', @customers,  (SELECT COUNT(*) FROM mart.customer_summary)
UNION ALL SELECT 'customer_summary', 'revenue',          @delivered_revenue, (SELECT SUM(revenue) FROM mart.customer_summary)
UNION ALL SELECT 'customer_summary', 'orders',           @all_orders,        (SELECT SUM(orders) FROM mart.customer_summary)
UNION ALL SELECT 'customer_summary', 'delivered orders', @delivered_orders,  (SELECT SUM(delivered_orders) FROM mart.customer_summary)
UNION ALL SELECT 'customer_summary', 'repeat customers', @repeat_customers,  (SELECT COUNT(*) FROM mart.customer_summary WHERE is_repeat = 1)
UNION ALL SELECT 'delivery_review', 'orders',
    (SELECT COUNT(*) FROM dw.fct_order WHERE is_revenue = 1 AND days_late IS NOT NULL AND review_score IS NOT NULL),
    (SELECT SUM(orders) FROM mart.delivery_review)
UNION ALL SELECT 'delivery_review', 'sum of review scores',
    (SELECT SUM(review_score) FROM dw.fct_order WHERE is_revenue = 1 AND days_late IS NOT NULL AND review_score IS NOT NULL),
    (SELECT SUM(review_score_sum) FROM mart.delivery_review)
UNION ALL SELECT 'seller_performance', 'sellers given a late-rate decile = sellers with 50+ single-seller orders',
    (SELECT COUNT(*) FROM mart.seller_performance WHERE single_seller_orders >= 50),
    (SELECT COUNT(*) FROM mart.seller_performance WHERE late_rate_decile IS NOT NULL);

SELECT check_group, check_name, expected, actual, result
FROM #checks
ORDER BY CASE result WHEN 'FAIL' THEN 0 ELSE 1 END, check_group, check_name;

IF EXISTS (SELECT 1 FROM #checks WHERE result = 'FAIL')
    THROW 50004, 'Mart checks failed. See the results above.', 1;

DECLARE @check_count INT = (SELECT COUNT(*) FROM #checks);
PRINT CONCAT('All ', @check_count, ' mart checks passed.');
GO
