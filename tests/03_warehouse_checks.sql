/*
Checks that the star schema is complete, has no repeated rows, and applies the
decisions in docs/assumptions.md correctly.

1. Row counts: every fact has exactly as many rows as its staging source.
2. Control totals: money and counts summed in the warehouse equal the staging
   totals, which proves no join repeated or dropped rows.
3. Customer history: the Type 2 customer dimension has one current version per
   customer, versions don't overlap or leave gaps, and every order is linked to
   the location it was actually placed from.
4. Business rules: revenue flag, review choice, product categories.
5. Constraints: every foreign key is enabled and trusted.

Returns one row per check, then raises an error if any check failed.
*/
USE EcommerceDW;
GO

SET NOCOUNT ON;

DROP TABLE IF EXISTS #checks;
CREATE TABLE #checks (
    check_group VARCHAR(20)    NOT NULL,
    check_name  NVARCHAR(200)  NOT NULL,
    expected    DECIMAL(19, 4) NOT NULL,
    actual      DECIMAL(19, 4) NOT NULL,
    result      AS CASE WHEN expected = actual THEN 'PASS' ELSE 'FAIL' END
);

-- 1. Row counts
INSERT INTO #checks (check_group, check_name, expected, actual)
SELECT 'row count', 'fct_order = staging orders',                (SELECT COUNT_BIG(*) FROM stg.orders),         (SELECT COUNT_BIG(*) FROM dw.fct_order)
UNION ALL SELECT 'row count', 'fct_order_item = staging order items',      (SELECT COUNT_BIG(*) FROM stg.order_items),    (SELECT COUNT_BIG(*) FROM dw.fct_order_item)
UNION ALL SELECT 'row count', 'fct_payment = staging payments',            (SELECT COUNT_BIG(*) FROM stg.order_payments), (SELECT COUNT_BIG(*) FROM dw.fct_payment)
UNION ALL SELECT 'row count', 'fct_review = staging reviews',              (SELECT COUNT_BIG(*) FROM stg.order_reviews),  (SELECT COUNT_BIG(*) FROM dw.fct_review)
UNION ALL SELECT 'row count', 'dim_product = staging products',           (SELECT COUNT_BIG(*) FROM stg.products),       (SELECT COUNT_BIG(*) FROM dw.dim_product)
UNION ALL SELECT 'row count', 'dim_seller = staging sellers',             (SELECT COUNT_BIG(*) FROM stg.sellers),        (SELECT COUNT_BIG(*) FROM dw.dim_seller)
UNION ALL SELECT 'row count', 'dim_customer covers every customer',
    (SELECT COUNT(DISTINCT customer_unique_id) FROM stg.customers),
    (SELECT COUNT(DISTINCT customer_unique_id) FROM dw.dim_customer);

-- 2. Control totals: order-level totals must equal the sums of the detail rows
INSERT INTO #checks (check_group, check_name, expected, actual)
SELECT 'control total', 'sum of fct_order_item.price',       (SELECT SUM(price) FROM stg.order_items),            (SELECT SUM(price) FROM dw.fct_order_item)
UNION ALL SELECT 'control total', 'sum of fct_order.item_total',       (SELECT SUM(price) FROM stg.order_items),            (SELECT SUM(item_total) FROM dw.fct_order)
UNION ALL SELECT 'control total', 'sum of fct_order.freight_total',    (SELECT SUM(freight_value) FROM stg.order_items),    (SELECT SUM(freight_total) FROM dw.fct_order)
UNION ALL SELECT 'control total', 'sum of fct_payment.payment_value',  (SELECT SUM(payment_value) FROM stg.order_payments), (SELECT SUM(payment_value) FROM dw.fct_payment)
UNION ALL SELECT 'control total', 'sum of fct_order.payment_total',    (SELECT SUM(payment_value) FROM stg.order_payments), (SELECT SUM(payment_total) FROM dw.fct_order)
UNION ALL SELECT 'control total', 'sum of fct_order.item_count',       (SELECT COUNT_BIG(*) FROM stg.order_items),          (SELECT SUM(item_count) FROM dw.fct_order)
UNION ALL SELECT 'control total', 'sum of fct_order.payment_count',    (SELECT COUNT_BIG(*) FROM stg.order_payments),       (SELECT SUM(payment_count) FROM dw.fct_order)
UNION ALL SELECT 'control total', 'sum of fct_order.review_count',     (SELECT COUNT_BIG(*) FROM stg.order_reviews),        (SELECT SUM(review_count) FROM dw.fct_order);

-- 3. Customer history (slowly changing dimension, Type 2). Expected is 0 rows breaking the rule.
INSERT INTO #checks (check_group, check_name, expected, actual)
SELECT 'customer history', 'customers without exactly one current version', 0,
    (SELECT COUNT(*) FROM (
        SELECT customer_unique_id
        FROM dw.dim_customer
        GROUP BY customer_unique_id
        HAVING SUM(CAST(is_current AS INT)) <> 1
     ) AS bad)
UNION ALL SELECT 'customer history', 'versions that end before they start', 0,
    (SELECT COUNT(*) FROM dw.dim_customer WHERE valid_to <= valid_from)
UNION ALL SELECT 'customer history', 'gaps or overlaps between consecutive versions', 0,
    (SELECT COUNT(*) FROM (
        SELECT valid_to,
               LEAD(valid_from) OVER (PARTITION BY customer_unique_id ORDER BY version_number) AS next_valid_from
        FROM dw.dim_customer
     ) AS v
     WHERE next_valid_from IS NOT NULL AND next_valid_from <> valid_to)
UNION ALL SELECT 'customer history', 'orders linked to a location other than the one they were placed from', 0,
    (SELECT COUNT(*)
     FROM dw.fct_order AS fo
     INNER JOIN dw.dim_customer AS dc
         ON dc.customer_key = fo.customer_key
     INNER JOIN stg.orders AS o
         ON o.order_id = fo.order_id
     INNER JOIN stg.customers AS c
         ON c.customer_id = o.customer_id
     WHERE dc.customer_unique_id <> c.customer_unique_id
        OR dc.zip_code_prefix <> c.customer_zip_code_prefix
        OR dc.city <> c.customer_city
        OR dc.[state] <> c.customer_state);

-- 4. Business rules from docs/assumptions.md
INSERT INTO #checks (check_group, check_name, expected, actual)
SELECT 'business rule', 'decision 2: is_revenue is set exactly for delivered orders', 0,
    (SELECT COUNT(*) FROM dw.fct_order
     WHERE is_revenue <> CASE WHEN order_status = 'delivered' THEN 1 ELSE 0 END)
UNION ALL SELECT 'business rule', 'decision 2: order items carry their order''s revenue flag', 0,
    (SELECT COUNT(*) FROM dw.fct_order_item AS i
     INNER JOIN dw.fct_order AS o ON o.order_id = i.order_id
     WHERE i.is_revenue <> o.is_revenue)
UNION ALL SELECT 'business rule', 'decision 6: reviewed orders have exactly one latest review', 0,
    (SELECT COUNT(*) FROM (
        SELECT order_id FROM dw.fct_review
        GROUP BY order_id
        HAVING SUM(CAST(is_latest_for_order AS INT)) <> 1
     ) AS bad)
UNION ALL SELECT 'business rule', 'decision 6: order review_score is the latest review''s score', 0,
    (SELECT COUNT(*) FROM dw.fct_order AS o
     INNER JOIN dw.fct_review AS r
         ON r.order_id = o.order_id AND r.is_latest_for_order = 1
     WHERE o.review_score <> r.review_score)
UNION ALL SELECT 'business rule', 'decision 8: products labelled unknown = products without a category',
    (SELECT COUNT(*) FROM stg.products WHERE product_category_name IS NULL),
    (SELECT COUNT(*) FROM dw.dim_product WHERE category_name = N'unknown')
UNION ALL SELECT 'business rule', 'decision 9: coordinates lie inside Brazil', 0,
    (SELECT COUNT(*) FROM (
        SELECT latitude, longitude FROM dw.dim_customer
        UNION ALL SELECT latitude, longitude FROM dw.dim_seller
     ) AS points
     WHERE latitude NOT BETWEEN -33.8 AND 5.3 OR longitude NOT BETWEEN -74.0 AND -34.8)
UNION ALL SELECT 'business rule', 'decision 10: delivery_days is never negative', 0,
    (SELECT COUNT(*) FROM dw.fct_order WHERE delivery_days < 0);

-- 5. Constraints: a foreign key that is disabled, or was added WITH NOCHECK, doesn't guarantee anything.
-- 15 foreign keys: fct_order 4, fct_order_item 5, fct_payment 3, fct_review 3
INSERT INTO #checks (check_group, check_name, expected, actual)
SELECT 'constraint', 'foreign keys in the dw schema', 15,
    (SELECT COUNT(*) FROM sys.foreign_keys WHERE SCHEMA_NAME(schema_id) = N'dw')
UNION ALL SELECT 'constraint', 'foreign keys disabled or not trusted', 0,
    (SELECT COUNT(*) FROM sys.foreign_keys
     WHERE SCHEMA_NAME(schema_id) = N'dw' AND (is_disabled = 1 OR is_not_trusted = 1));

SELECT check_group, check_name, expected, actual, result
FROM #checks
ORDER BY CASE result WHEN 'FAIL' THEN 0 ELSE 1 END, check_group, check_name;

IF EXISTS (SELECT 1 FROM #checks WHERE result = 'FAIL')
    THROW 50003, 'Warehouse checks failed. See the results above.', 1;

DECLARE @check_count INT = (SELECT COUNT(*) FROM #checks);
PRINT CONCAT('All ', @check_count, ' warehouse checks passed.');
GO
