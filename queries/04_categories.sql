/*
Question 4: Which product categories sell most, and which receive the worst reviews?

Definitions:
- Revenue = item prices on delivered orders (decision 2), Jan 2017 to Aug 2018 (decision 3).
- Reviews are given per order, not per item. An order containing two categories counts
  once for each, so the per-category score answers "how were orders containing this
  category rated?"
- Late deliveries pull scores down (see 03_delivery_and_reviews.sql). The score on orders
  that arrived on time separates dissatisfaction with the product from delivery problems.
*/
USE EcommerceDW;
GO

-- 1. Categories by revenue, with each category's share and the running (Pareto) share
WITH by_category AS (
    SELECT
        p.category_name,
        COUNT(DISTINCT i.order_id) AS orders,
        COUNT(*)                   AS items,
        SUM(i.price)               AS revenue
    FROM dw.fct_order_item AS i
    INNER JOIN dw.dim_product AS p
        ON p.product_key = i.product_key
    INNER JOIN dw.dim_date AS d
        ON d.date_key = i.purchase_date_key
    WHERE i.is_revenue = 1
      AND d.in_analysis_window = 1
    GROUP BY p.category_name
)
SELECT TOP (15)
    RANK() OVER (ORDER BY revenue DESC)                                          AS revenue_rank,
    category_name,
    orders,
    revenue,
    CAST(revenue / items AS DECIMAL(10, 2))                                      AS avg_item_price,
    CAST(100.0 * revenue / SUM(revenue) OVER () AS DECIMAL(5, 1))                AS pct_of_revenue,
    CAST(100.0 * SUM(revenue) OVER (ORDER BY revenue DESC ROWS UNBOUNDED PRECEDING)
         / SUM(revenue) OVER () AS DECIMAL(5, 1))                                AS cumulative_pct,
    (SELECT COUNT(*) FROM by_category)                                           AS categories
FROM by_category
ORDER BY revenue DESC;

-- 2. Review scores by category (categories with 500+ reviewed orders), worst first.
-- DISTINCT gives one row per order and category, so an order with three items from the
-- same category is counted once.
WITH order_categories AS (
    SELECT DISTINCT
        i.order_id,
        p.category_name
    FROM dw.fct_order_item AS i
    INNER JOIN dw.dim_product AS p
        ON p.product_key = i.product_key
    INNER JOIN dw.dim_date AS d
        ON d.date_key = i.purchase_date_key
    WHERE i.is_revenue = 1
      AND d.in_analysis_window = 1
),
scored AS (
    SELECT
        oc.category_name,
        o.review_score,
        o.is_late
    FROM order_categories AS oc
    INNER JOIN dw.fct_order AS o
        ON o.order_id = oc.order_id
)
-- Scores are measured over reviewed orders and lateness over orders with a delivery date.
-- COUNT(column) and AVG skip NULLs, so each measure uses the orders it applies to.
SELECT TOP (10)
    category_name,
    COUNT(review_score)                                                                      AS reviewed_orders,
    CAST(AVG(CAST(review_score AS DECIMAL(5, 2))) AS DECIMAL(3, 2))                          AS avg_score,
    CAST(100.0 * SUM(CASE WHEN review_score = 1 THEN 1 ELSE 0 END) / COUNT(review_score) AS DECIMAL(5, 1)) AS one_star_pct,
    CAST(100.0 * AVG(CAST(is_late AS FLOAT)) AS DECIMAL(5, 1))                               AS late_pct,
    -- Score when delivery was not the problem
    CAST(AVG(CASE WHEN is_late = 0 THEN CAST(review_score AS DECIMAL(5, 2)) END) AS DECIMAL(3, 2)) AS avg_score_on_time
FROM scored
GROUP BY category_name
HAVING COUNT(review_score) >= 500
ORDER BY avg_score;

-- 3. The same measures for all orders, as a baseline to compare categories against
SELECT
    COUNT(o.review_score)                                                                    AS reviewed_orders,
    CAST(AVG(CAST(o.review_score AS DECIMAL(5, 2))) AS DECIMAL(3, 2))                        AS avg_score,
    CAST(100.0 * SUM(CASE WHEN o.review_score = 1 THEN 1 ELSE 0 END) / COUNT(o.review_score) AS DECIMAL(5, 1)) AS one_star_pct,
    CAST(100.0 * AVG(CAST(o.is_late AS FLOAT)) AS DECIMAL(5, 1))                             AS late_pct,
    CAST(AVG(CASE WHEN o.is_late = 0 THEN CAST(o.review_score AS DECIMAL(5, 2)) END) AS DECIMAL(3, 2)) AS avg_score_on_time
FROM dw.fct_order AS o
INNER JOIN dw.dim_date AS d
    ON d.date_key = o.purchase_date_key
WHERE o.is_revenue = 1
  AND d.in_analysis_window = 1;

-- 4. Watch list: top-20 revenue categories whose on-time score is at least 0.05 below the
-- baseline (smaller gaps are rounding noise). These are big categories where customers are
-- unhappy even when delivery went well, which points at the products or their descriptions
-- rather than logistics.
WITH order_categories AS (
    SELECT DISTINCT i.order_id, p.category_name
    FROM dw.fct_order_item AS i
    INNER JOIN dw.dim_product AS p
        ON p.product_key = i.product_key
    INNER JOIN dw.dim_date AS d
        ON d.date_key = i.purchase_date_key
    WHERE i.is_revenue = 1
      AND d.in_analysis_window = 1
),
revenue_rank AS (
    SELECT
        p.category_name,
        RANK() OVER (ORDER BY SUM(i.price) DESC) AS revenue_rank
    FROM dw.fct_order_item AS i
    INNER JOIN dw.dim_product AS p
        ON p.product_key = i.product_key
    INNER JOIN dw.dim_date AS d
        ON d.date_key = i.purchase_date_key
    WHERE i.is_revenue = 1
      AND d.in_analysis_window = 1
    GROUP BY p.category_name
),
on_time_scores AS (
    SELECT
        oc.category_name,
        COUNT(*)                                       AS on_time_reviewed_orders,
        AVG(CAST(o.review_score AS DECIMAL(5, 2)))     AS avg_score_on_time
    FROM order_categories AS oc
    INNER JOIN dw.fct_order AS o
        ON o.order_id = oc.order_id
    WHERE o.review_score IS NOT NULL
      AND o.is_late = 0
    GROUP BY oc.category_name
),
baseline AS (
    SELECT AVG(CAST(o.review_score AS DECIMAL(5, 2))) AS avg_score_on_time
    FROM dw.fct_order AS o
    INNER JOIN dw.dim_date AS d
        ON d.date_key = o.purchase_date_key
    WHERE o.is_revenue = 1
      AND d.in_analysis_window = 1
      AND o.review_score IS NOT NULL
      AND o.is_late = 0
)
SELECT
    r.revenue_rank,
    s.category_name,
    s.on_time_reviewed_orders,
    CAST(s.avg_score_on_time AS DECIMAL(3, 2))                     AS avg_score_on_time,
    CAST(s.avg_score_on_time - b.avg_score_on_time AS DECIMAL(4, 2)) AS vs_baseline
FROM on_time_scores AS s
INNER JOIN revenue_rank AS r
    ON r.category_name = s.category_name
CROSS JOIN baseline AS b
WHERE r.revenue_rank <= 20
  AND s.avg_score_on_time <= b.avg_score_on_time - 0.05
ORDER BY vs_baseline;
