/*
Question 3: Which sellers deliver late, and how does late delivery affect review scores?

Definitions (docs/assumptions.md, decision 10):
- Delivery time is purchase to delivered to the customer, for delivered orders with a
  delivered date. Carrier and approval timestamps are not used.
- An order is late when it arrives on a later date than the estimated delivery date.
- An order's review score is its most recently answered review (decision 6).
*/
USE EcommerceDW;
GO

-- 1. Delivery performance by month: days promised at purchase, average and median days
-- taken, and the share delivered late. Lateness depends on both speed and the promise.
WITH delivered AS (
    SELECT
        d.month_start,
        d.year_month,
        DATEDIFF(DAY, o.purchase_timestamp, o.estimated_delivery_date) AS promised_days,
        o.delivery_days,
        o.is_late
    FROM dw.fct_order AS o
    INNER JOIN dw.dim_date AS d
        ON d.date_key = o.purchase_date_key
    WHERE o.is_revenue = 1
      AND o.delivery_days IS NOT NULL
      AND d.in_analysis_window = 1
)
-- PERCENTILE_CONT only exists as a window function in SQL Server, so every measure here is a
-- window over the month and DISTINCT keeps one row per month
SELECT DISTINCT
    year_month,
    COUNT(*)                         OVER (PARTITION BY month_start)                           AS orders,
    CAST(AVG(CAST(promised_days AS DECIMAL(6, 2))) OVER (PARTITION BY month_start) AS DECIMAL(5, 1)) AS avg_promised_days,
    CAST(AVG(delivery_days)          OVER (PARTITION BY month_start) AS DECIMAL(5, 1))         AS avg_days,
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY delivery_days)
                                     OVER (PARTITION BY month_start) AS DECIMAL(5, 1))         AS median_days,
    CAST(100.0 * AVG(CAST(is_late AS FLOAT)) OVER (PARTITION BY month_start) AS DECIMAL(5, 1)) AS late_pct
FROM delivered
ORDER BY year_month;

-- 2. Review score by how early or late the order arrived
WITH reviewed AS (
    SELECT
        CASE
            WHEN days_late <= -15 THEN '1. 15+ days early'
            WHEN days_late <= -8  THEN '2. 8-14 days early'
            WHEN days_late <= -1  THEN '3. 1-7 days early'
            WHEN days_late = 0    THEN '4. on the estimated day'
            WHEN days_late <= 3   THEN '5. 1-3 days late'
            WHEN days_late <= 7   THEN '6. 4-7 days late'
            ELSE                       '7. 8+ days late'
        END AS arrival,
        review_score
    FROM dw.fct_order
    WHERE is_revenue = 1
      AND days_late IS NOT NULL
      AND review_score IS NOT NULL
)
SELECT
    arrival,
    COUNT(*)                                                                  AS orders,
    CAST(AVG(CAST(review_score AS DECIMAL(5, 2))) AS DECIMAL(3, 2))           AS avg_score,
    CAST(100.0 * SUM(CASE WHEN review_score = 1 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5, 1)) AS one_star_pct,
    CAST(100.0 * SUM(CASE WHEN review_score = 5 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5, 1)) AS five_star_pct
FROM reviewed
GROUP BY arrival
ORDER BY arrival;

-- 3. Sellers with the highest late-delivery rates.
-- Lateness is recorded per order, so only single-seller orders are used here: in an order
-- with several sellers, there is no way to tell which seller's parcel was late.
-- Sellers need at least 50 such orders, so one bad week can't put a small seller on top.
WITH seller_orders AS (
    SELECT DISTINCT
        i.seller_key,
        o.order_id,
        o.is_late,
        o.delivery_days,
        o.review_score
    FROM dw.fct_order_item AS i
    INNER JOIN dw.fct_order AS o
        ON o.order_id = i.order_id
    WHERE o.is_revenue = 1
      AND o.seller_count = 1
      AND o.is_late IS NOT NULL
),
per_seller AS (
    SELECT
        seller_key,
        COUNT(*)                                     AS orders,
        SUM(CAST(is_late AS INT))                    AS late_orders,
        AVG(CAST(is_late AS FLOAT))                  AS late_rate,
        AVG(delivery_days)                           AS avg_days,
        AVG(CAST(review_score AS DECIMAL(5, 2)))     AS avg_score
    FROM seller_orders
    GROUP BY seller_key
    HAVING COUNT(*) >= 50
)
SELECT TOP (10)
    s.seller_id,
    s.[state],
    p.orders,
    p.late_orders,
    CAST(100 * p.late_rate AS DECIMAL(5, 1)) AS late_pct,
    CAST(p.avg_days AS DECIMAL(5, 1))        AS avg_days,
    CAST(p.avg_score AS DECIMAL(3, 2))       AS avg_score
FROM per_seller AS p
INNER JOIN dw.dim_seller AS s
    ON s.seller_key = p.seller_key
ORDER BY p.late_rate DESC, p.orders DESC;

-- 4. Is lateness caused by a few bad sellers, or spread across the platform?
-- Sellers with 50+ single-seller orders are split into ten equal groups (deciles) by
-- late-delivery RATE. Ranking by the NUMBER of late orders would mostly rank sellers by size.
-- If a few sellers caused the problem, the worst decile's share of late orders would be far
-- above its share of orders.
WITH seller_orders AS (
    SELECT DISTINCT i.seller_key, o.order_id, o.is_late
    FROM dw.fct_order_item AS i
    INNER JOIN dw.fct_order AS o
        ON o.order_id = i.order_id
    WHERE o.is_revenue = 1
      AND o.seller_count = 1
      AND o.is_late IS NOT NULL
),
per_seller AS (
    SELECT seller_key, COUNT(*) AS orders, SUM(CAST(is_late AS INT)) AS late_orders
    FROM seller_orders
    GROUP BY seller_key
    HAVING COUNT(*) >= 50
),
deciles AS (
    SELECT
        orders,
        late_orders,
        NTILE(10) OVER (ORDER BY 1.0 * late_orders / orders DESC, seller_key) AS decile  -- 1 = latest
    FROM per_seller
)
SELECT
    decile,
    COUNT(*)                                                                         AS sellers,
    SUM(orders)                                                                      AS orders,
    SUM(late_orders)                                                                 AS late_orders,
    CAST(100.0 * SUM(late_orders) / SUM(orders) AS DECIMAL(5, 1))                    AS late_pct,
    CAST(100.0 * SUM(late_orders) / SUM(SUM(late_orders)) OVER () AS DECIMAL(5, 1))  AS pct_of_late_orders,
    CAST(100.0 * SUM(orders) / SUM(SUM(orders)) OVER () AS DECIMAL(5, 1))            AS pct_of_orders
FROM deciles
GROUP BY decile
ORDER BY decile;

-- 5. Delivery by customer state: slowest states first (states with 100+ delivered orders)
SELECT
    c.[state],
    COUNT(*)                                                        AS orders,
    CAST(AVG(o.delivery_days) AS DECIMAL(5, 1))                     AS avg_days,
    CAST(100.0 * AVG(CAST(o.is_late AS FLOAT)) AS DECIMAL(5, 1))    AS late_pct,
    CAST(AVG(CAST(o.review_score AS DECIMAL(5, 2))) AS DECIMAL(3, 2)) AS avg_score
FROM dw.fct_order AS o
INNER JOIN dw.dim_customer AS c
    ON c.customer_key = o.customer_key
INNER JOIN dw.dim_date AS d
    ON d.date_key = o.purchase_date_key
WHERE o.is_revenue = 1
  AND o.delivery_days IS NOT NULL
  AND d.in_analysis_window = 1
GROUP BY c.[state]
HAVING COUNT(*) >= 100
ORDER BY avg_days DESC;
