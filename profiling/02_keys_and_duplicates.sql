/*
Which columns uniquely identify a row in each table?

A column (or set of columns) is a usable key when the number of distinct key
values equals the number of rows. duplicate_rows = rows - distinct keys.
*/
USE EcommerceDW;
GO

SELECT table_name, key_columns, row_count, distinct_keys, row_count - distinct_keys AS duplicate_rows
FROM (
    SELECT 'orders' AS table_name, 'order_id' AS key_columns,
           (SELECT COUNT(*) FROM stg.orders) AS row_count,
           (SELECT COUNT(DISTINCT order_id) FROM stg.orders) AS distinct_keys
    UNION ALL
    SELECT 'customers', 'customer_id',
           (SELECT COUNT(*) FROM stg.customers),
           (SELECT COUNT(DISTINCT customer_id) FROM stg.customers)
    UNION ALL
    SELECT 'customers', 'customer_unique_id',
           (SELECT COUNT(*) FROM stg.customers),
           (SELECT COUNT(DISTINCT customer_unique_id) FROM stg.customers)
    UNION ALL
    SELECT 'products', 'product_id',
           (SELECT COUNT(*) FROM stg.products),
           (SELECT COUNT(DISTINCT product_id) FROM stg.products)
    UNION ALL
    SELECT 'sellers', 'seller_id',
           (SELECT COUNT(*) FROM stg.sellers),
           (SELECT COUNT(DISTINCT seller_id) FROM stg.sellers)
    UNION ALL
    SELECT 'category_translation', 'product_category_name',
           (SELECT COUNT(*) FROM stg.category_translation),
           (SELECT COUNT(DISTINCT product_category_name) FROM stg.category_translation)
    UNION ALL
    SELECT 'order_items', 'order_id + order_item_id',
           (SELECT COUNT(*) FROM stg.order_items),
           (SELECT COUNT(*) FROM (SELECT DISTINCT order_id, order_item_id FROM stg.order_items) AS k)
    UNION ALL
    SELECT 'order_payments', 'order_id + payment_sequential',
           (SELECT COUNT(*) FROM stg.order_payments),
           (SELECT COUNT(*) FROM (SELECT DISTINCT order_id, payment_sequential FROM stg.order_payments) AS k)
    UNION ALL
    SELECT 'order_reviews', 'review_id',
           (SELECT COUNT(*) FROM stg.order_reviews),
           (SELECT COUNT(DISTINCT review_id) FROM stg.order_reviews)
    UNION ALL
    SELECT 'order_reviews', 'order_id',
           (SELECT COUNT(*) FROM stg.order_reviews),
           (SELECT COUNT(DISTINCT order_id) FROM stg.order_reviews)
    UNION ALL
    SELECT 'order_reviews', 'review_id + order_id',
           (SELECT COUNT(*) FROM stg.order_reviews),
           (SELECT COUNT(*) FROM (SELECT DISTINCT review_id, order_id FROM stg.order_reviews) AS k)
    UNION ALL
    SELECT 'geolocation', 'geolocation_zip_code_prefix',
           (SELECT COUNT(*) FROM stg.geolocation),
           (SELECT COUNT(DISTINCT geolocation_zip_code_prefix) FROM stg.geolocation)
) AS keys
ORDER BY table_name, key_columns;

-- Are order_item_id values numbered 1, 2, 3... with no gaps within each order?
SELECT
    COUNT(*)                                                    AS orders_with_items,
    SUM(CASE WHEN max_item = item_count THEN 1 ELSE 0 END)      AS numbered_without_gaps,
    SUM(CASE WHEN max_item <> item_count THEN 1 ELSE 0 END)     AS numbered_with_gaps
FROM (
    SELECT order_id, MAX(order_item_id) AS max_item, COUNT(*) AS item_count
    FROM stg.order_items
    GROUP BY order_id
) AS per_order;

-- Duplicate review_ids: is it the same review attached to several orders?
WITH duplicated AS (
    SELECT review_id
    FROM stg.order_reviews
    GROUP BY review_id
    HAVING COUNT(*) > 1
)
SELECT
    COUNT(DISTINCT r.review_id)                                        AS duplicated_review_ids,
    COUNT(*)                                                           AS rows_involved,
    COUNT(DISTINCT CONCAT(r.review_id, '|', r.review_score, '|', r.review_comment_message)) AS distinct_review_contents
FROM stg.order_reviews AS r
INNER JOIN duplicated AS d
    ON d.review_id = r.review_id;

-- Orders with more than one review: how many, and do the scores disagree?
WITH per_order AS (
    SELECT order_id, COUNT(*) AS reviews, MIN(review_score) AS min_score, MAX(review_score) AS max_score
    FROM stg.order_reviews
    GROUP BY order_id
    HAVING COUNT(*) > 1
)
SELECT
    COUNT(*)                                                    AS orders_with_several_reviews,
    SUM(reviews)                                                AS review_rows,
    SUM(CASE WHEN min_score <> max_score THEN 1 ELSE 0 END)    AS orders_with_conflicting_scores
FROM per_order;
