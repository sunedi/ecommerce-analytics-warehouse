/*
Are the values plausible?

Zero, negative, missing and out-of-range values that would distort sums,
averages or maps.
*/
USE EcommerceDW;
GO

-- 1. Suspicious amounts and measurements
SELECT finding, rows_affected
FROM (
    SELECT 1 AS sort_order, 'order items with price 0 or less' AS finding,
           (SELECT COUNT(*) FROM stg.order_items WHERE price <= 0) AS rows_affected
    UNION ALL
    SELECT 2, 'order items with free freight (0.00)',
           (SELECT COUNT(*) FROM stg.order_items WHERE freight_value = 0)
    UNION ALL
    SELECT 3, 'payments of 0.00',
           (SELECT COUNT(*) FROM stg.order_payments WHERE payment_value = 0)
    UNION ALL
    SELECT 4, 'payments with 0 instalments',
           (SELECT COUNT(*) FROM stg.order_payments WHERE payment_installments = 0)
    UNION ALL
    SELECT 5, 'payments with type not_defined',
           (SELECT COUNT(*) FROM stg.order_payments WHERE payment_type = 'not_defined')
    UNION ALL
    SELECT 6, 'products weighing 0 g',
           (SELECT COUNT(*) FROM stg.products WHERE product_weight_g = 0)
    UNION ALL
    SELECT 7, 'products with no category',
           (SELECT COUNT(*) FROM stg.products WHERE product_category_name IS NULL)
    UNION ALL
    SELECT 8, 'products with no dimensions',
           (SELECT COUNT(*) FROM stg.products WHERE product_weight_g IS NULL)
    UNION ALL
    SELECT 9, 'order items with a shipping limit after 2018',
           (SELECT COUNT(*) FROM stg.order_items WHERE shipping_limit_date >= '2019-01-01')
    UNION ALL
    SELECT 10, 'reviews answered before they were created',
           (SELECT COUNT(*) FROM stg.order_reviews WHERE review_answer_timestamp < review_creation_date)
    UNION ALL
    SELECT 11, 'reviews created before the order was purchased',
           (SELECT COUNT(*) FROM stg.order_reviews AS r
            INNER JOIN stg.orders AS o
                ON o.order_id = r.order_id
            WHERE r.review_creation_date < CAST(o.order_purchase_timestamp AS DATE))
    UNION ALL
    -- Brazil lies roughly between latitudes 5.3 N and 33.8 S, and longitudes 34.8 W and 74.0 W
    SELECT 12, 'geolocation points outside Brazil',
           (SELECT COUNT(*) FROM stg.geolocation
            WHERE geolocation_lat NOT BETWEEN -33.8 AND 5.3
               OR geolocation_lng NOT BETWEEN -74.0 AND -34.8)
) AS findings
ORDER BY sort_order;

-- 2. Payment types
SELECT
    payment_type,
    COUNT(*)                  AS payments,
    COUNT(DISTINCT order_id)  AS orders,
    SUM(payment_value)        AS total_value
FROM stg.order_payments
GROUP BY payment_type
ORDER BY payments DESC;

-- 3. Review scores
SELECT
    review_score,
    COUNT(*)                                                    AS reviews,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5, 1)) AS pct
FROM stg.order_reviews
GROUP BY review_score
ORDER BY review_score;

-- 4. Price and freight distribution.
-- PERCENTILE_CONT is a window function in SQL Server, so it returns the same value on every
-- row; DISTINCT keeps one. It returns FLOAT, so the results are cast back to money.
SELECT DISTINCT
    CAST(PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY price)         OVER () AS DECIMAL(10, 2)) AS median_price,
    CAST(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY price)         OVER () AS DECIMAL(10, 2)) AS p99_price,
    CAST(PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY freight_value) OVER () AS DECIMAL(10, 2)) AS median_freight,
    CAST(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY freight_value) OVER () AS DECIMAL(10, 2)) AS p99_freight
FROM stg.order_items;
