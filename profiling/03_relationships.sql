/*
Do the tables link up?

An orphan is a row whose foreign key has no matching row in the parent table.
Orphans silently disappear from INNER JOINs, so they must be counted before
any join is trusted. NOT EXISTS (an "anti-join") finds them.
*/
USE EcommerceDW;
GO

-- 1. Child rows whose parent is missing
SELECT relationship, child_rows, orphan_rows
FROM (
    SELECT 1 AS sort_order, 'order_items -> orders' AS relationship,
           (SELECT COUNT(*) FROM stg.order_items) AS child_rows,
           (SELECT COUNT(*) FROM stg.order_items AS c
            WHERE NOT EXISTS (SELECT 1 FROM stg.orders AS o WHERE o.order_id = c.order_id)) AS orphan_rows
    UNION ALL
    SELECT 2, 'order_items -> products',
           (SELECT COUNT(*) FROM stg.order_items),
           (SELECT COUNT(*) FROM stg.order_items AS c
            WHERE NOT EXISTS (SELECT 1 FROM stg.products AS p WHERE p.product_id = c.product_id))
    UNION ALL
    SELECT 3, 'order_items -> sellers',
           (SELECT COUNT(*) FROM stg.order_items),
           (SELECT COUNT(*) FROM stg.order_items AS c
            WHERE NOT EXISTS (SELECT 1 FROM stg.sellers AS s WHERE s.seller_id = c.seller_id))
    UNION ALL
    SELECT 4, 'order_payments -> orders',
           (SELECT COUNT(*) FROM stg.order_payments),
           (SELECT COUNT(*) FROM stg.order_payments AS c
            WHERE NOT EXISTS (SELECT 1 FROM stg.orders AS o WHERE o.order_id = c.order_id))
    UNION ALL
    SELECT 5, 'order_reviews -> orders',
           (SELECT COUNT(*) FROM stg.order_reviews),
           (SELECT COUNT(*) FROM stg.order_reviews AS c
            WHERE NOT EXISTS (SELECT 1 FROM stg.orders AS o WHERE o.order_id = c.order_id))
    UNION ALL
    SELECT 6, 'orders -> customers',
           (SELECT COUNT(*) FROM stg.orders),
           (SELECT COUNT(*) FROM stg.orders AS c
            WHERE NOT EXISTS (SELECT 1 FROM stg.customers AS cu WHERE cu.customer_id = c.customer_id))
    UNION ALL
    SELECT 7, 'products -> category_translation (products with a category)',
           (SELECT COUNT(*) FROM stg.products WHERE product_category_name IS NOT NULL),
           (SELECT COUNT(*) FROM stg.products AS c
            WHERE c.product_category_name IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM stg.category_translation AS t WHERE t.product_category_name = c.product_category_name))
    UNION ALL
    SELECT 8, 'customers -> geolocation (ZIP prefix)',
           (SELECT COUNT(*) FROM stg.customers),
           (SELECT COUNT(*) FROM stg.customers AS c
            WHERE NOT EXISTS (SELECT 1 FROM stg.geolocation AS g WHERE g.geolocation_zip_code_prefix = c.customer_zip_code_prefix))
    UNION ALL
    SELECT 9, 'sellers -> geolocation (ZIP prefix)',
           (SELECT COUNT(*) FROM stg.sellers),
           (SELECT COUNT(*) FROM stg.sellers AS c
            WHERE NOT EXISTS (SELECT 1 FROM stg.geolocation AS g WHERE g.geolocation_zip_code_prefix = c.seller_zip_code_prefix))
) AS checks
ORDER BY sort_order;

-- 2. Categories used by products but missing from the translation table
SELECT p.product_category_name, COUNT(*) AS products
FROM stg.products AS p
WHERE p.product_category_name IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM stg.category_translation AS t WHERE t.product_category_name = p.product_category_name)
GROUP BY p.product_category_name;

-- 3. Orders without items, payments or a review, by status.
-- Each child table is reduced to one row per order (DISTINCT) before the LEFT JOIN,
-- so an order with three items still counts once.
SELECT
    o.order_status,
    COUNT(*)                                             AS orders,
    SUM(CASE WHEN i.order_id IS NULL THEN 1 ELSE 0 END) AS without_items,
    SUM(CASE WHEN p.order_id IS NULL THEN 1 ELSE 0 END) AS without_payments,
    SUM(CASE WHEN r.order_id IS NULL THEN 1 ELSE 0 END) AS without_review
FROM stg.orders AS o
LEFT JOIN (SELECT DISTINCT order_id FROM stg.order_items)    AS i ON i.order_id = o.order_id
LEFT JOIN (SELECT DISTINCT order_id FROM stg.order_payments) AS p ON p.order_id = o.order_id
LEFT JOIN (SELECT DISTINCT order_id FROM stg.order_reviews)  AS r ON r.order_id = o.order_id
GROUP BY o.order_status
ORDER BY orders DESC;

-- 4. Do payments add up to item prices plus freight?
-- Items and payments are summed to one row per order *before* joining. Joining the
-- detail rows would pair every item with every payment and inflate both totals.
WITH items AS (
    SELECT order_id, SUM(price) AS item_total, SUM(freight_value) AS freight_total
    FROM stg.order_items
    GROUP BY order_id
),
payments AS (
    SELECT order_id, SUM(payment_value) AS payment_total
    FROM stg.order_payments
    GROUP BY order_id
),
compared AS (
    SELECT
        i.order_id,
        p.payment_total - (i.item_total + i.freight_total) AS difference
    FROM items AS i
    INNER JOIN payments AS p
        ON p.order_id = i.order_id
),
classified AS (
    SELECT
        difference,
        CASE
            WHEN ABS(difference) <= 0.01 THEN '1. matches (within 1 centavo)'
            WHEN difference > 0          THEN '2. paid more than items + freight'
            ELSE                              '3. paid less than items + freight'
        END AS payment_vs_items
    FROM compared
)
SELECT payment_vs_items, COUNT(*) AS orders, SUM(difference) AS total_difference
FROM classified
GROUP BY payment_vs_items
ORDER BY payment_vs_items;
