/*
Question 2: How do repeat customers differ from one-time buyers?

Definitions:
- A customer is a customer_unique_id (decision 4). A customer who moved has several
  rows in dim_customer, so customers are always counted with COUNT(DISTINCT ...).
- Only delivered orders count (decision 2). A repeat customer has 2 or more.
- Orders placed on the same calendar day are treated as one visit when measuring
  whether a customer came back: two baskets bought minutes apart are not loyalty.
*/
USE EcommerceDW;
GO

-- Every delivered order, numbered in time order within its customer
DROP TABLE IF EXISTS #customer_orders;

SELECT
    c.customer_unique_id,
    o.order_id,
    o.purchase_timestamp,
    o.item_total,
    o.review_score,
    o.is_late,
    ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id ORDER BY o.purchase_timestamp, o.order_id) AS order_number,
    COUNT(*)     OVER (PARTITION BY c.customer_unique_id)                                        AS customer_order_count
INTO #customer_orders
FROM dw.fct_order AS o
INNER JOIN dw.dim_customer AS c
    ON c.customer_key = o.customer_key
WHERE o.is_revenue = 1;

-- 1. One-time against repeat customers: how many, and how much they spend
WITH customer_type AS (
    SELECT
        customer_unique_id,
        CASE WHEN customer_order_count > 1 THEN 'repeat' ELSE 'one-time' END AS customer_type,
        COUNT(*)         AS orders,
        SUM(item_total)  AS revenue
    FROM #customer_orders
    GROUP BY customer_unique_id, customer_order_count
)
SELECT
    customer_type,
    COUNT(*)                                                         AS customers,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5, 1))  AS pct_of_customers,
    SUM(orders)                                                      AS orders,
    SUM(revenue)                                                     AS revenue,
    CAST(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER () AS DECIMAL(5, 1)) AS pct_of_revenue,
    CAST(SUM(revenue) / SUM(orders) AS DECIMAL(10, 2))               AS avg_order_value,
    CAST(SUM(revenue) / COUNT(*) AS DECIMAL(10, 2))                  AS revenue_per_customer
FROM customer_type
GROUP BY customer_type;

-- 2. How long until the second order? Same-day second orders are shown separately.
WITH first_two AS (
    SELECT
        customer_unique_id,
        MAX(CASE WHEN order_number = 1 THEN purchase_timestamp END) AS first_order_at,
        MAX(CASE WHEN order_number = 2 THEN purchase_timestamp END) AS second_order_at
    FROM #customer_orders
    WHERE customer_order_count > 1
    GROUP BY customer_unique_id
),
gaps AS (
    SELECT DATEDIFF(DAY, first_order_at, second_order_at) AS days_between
    FROM first_two
)
SELECT
    CASE
        WHEN days_between = 0    THEN '1. same day'
        WHEN days_between <= 30  THEN '2. 1-30 days'
        WHEN days_between <= 90  THEN '3. 31-90 days'
        WHEN days_between <= 180 THEN '4. 91-180 days'
        ELSE                          '5. over 180 days'
    END                                                             AS time_to_second_order,
    COUNT(*)                                                        AS customers,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5, 1)) AS pct
FROM gaps
GROUP BY
    CASE
        WHEN days_between = 0    THEN '1. same day'
        WHEN days_between <= 30  THEN '2. 1-30 days'
        WHEN days_between <= 90  THEN '3. 31-90 days'
        WHEN days_between <= 180 THEN '4. 91-180 days'
        ELSE                          '5. over 180 days'
    END
ORDER BY time_to_second_order;

-- 3. Does the first order's experience affect whether a customer comes back?
-- "Came back" = another delivered order 1 to 180 days after the first.
-- Only customers whose first order was on or before 2018-03-03 are included, so every
-- one of them had a full 180 days to come back before the data ends (2018-08-31).
-- Without this cut-off, recent customers would look disloyal only because time ran out.
--
-- Each rate comes with a 95% confidence interval: p +/- 1.96 * SQRT(p * (1 - p) / n).
-- If two groups' intervals don't overlap, the difference is very unlikely to be chance.
-- If they overlap, the difference may be noise and shouldn't be reported as a finding.
-- (The formula is unreliable for very small groups or rates near 0, e.g. "no delivery date".)
--
-- The outcome is saved to a temp table once. A CTE is re-run every time it is referenced,
-- and it is referenced three times below.
DROP TABLE IF EXISTS #outcomes;

SELECT
    f.customer_unique_id,
    f.review_score,
    f.is_late,
    -- Joining on customer only (an equality join SQL Server can hash) and testing the gap
    -- afterwards is far faster than a correlated subquery with DATEDIFF in its WHERE clause
    MAX(CASE WHEN DATEDIFF(DAY, f.purchase_timestamp, later.purchase_timestamp) BETWEEN 1 AND 180 THEN 1 ELSE 0 END) AS came_back
INTO #outcomes
FROM #customer_orders AS f
LEFT JOIN #customer_orders AS later
    ON  later.customer_unique_id = f.customer_unique_id
    AND later.order_number > 1
WHERE f.order_number = 1
  AND f.purchase_timestamp >= '2017-01-01'
  AND f.purchase_timestamp <  '2018-03-04'
GROUP BY f.customer_unique_id, f.review_score, f.is_late;

WITH grouped AS (
    SELECT
        'first order review score'                             AS split_by,
        ISNULL(CAST(review_score AS VARCHAR(10)), 'no review') AS [group],
        COUNT(*)                                               AS customers,
        AVG(CAST(came_back AS FLOAT))                          AS rate
    FROM #outcomes
    GROUP BY review_score
    UNION ALL
    SELECT
        'first order delivery',
        CASE is_late WHEN 1 THEN 'late' WHEN 0 THEN 'on time' ELSE 'no delivery date' END,
        COUNT(*),
        AVG(CAST(came_back AS FLOAT))
    FROM #outcomes
    GROUP BY is_late
    UNION ALL
    SELECT 'all', 'all customers in the window', COUNT(*), AVG(CAST(came_back AS FLOAT))
    FROM #outcomes
)
SELECT
    split_by,
    [group],
    customers,
    CAST(100 * rate AS DECIMAL(5, 2))                                             AS came_back_pct,
    CAST(100 * (rate - 1.96 * SQRT(rate * (1 - rate) / customers)) AS DECIMAL(5, 2)) AS ci_low_pct,
    CAST(100 * (rate + 1.96 * SQRT(rate * (1 - rate) / customers)) AS DECIMAL(5, 2)) AS ci_high_pct
FROM grouped
ORDER BY split_by, [group];
