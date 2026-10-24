/*
Question 1: What drives monthly revenue, and how much of what customers pay is freight?

Definitions (docs/assumptions.md, docs/data_model.md):
- Revenue = item prices on delivered orders (decision 2), dated by purchase (decision 1).
- Monthly figures use the complete months, Jan 2017 to Aug 2018 (decision 3).
- Freight is kept separate from revenue; its share is freight / (revenue + freight),
  i.e. the part of what the customer paid for goods and delivery that was delivery.
*/
USE EcommerceDW;
GO

-- 1. Month by month: orders, revenue, average order value, freight share and growth
WITH monthly AS (
    SELECT
        d.month_start,
        d.year_month,
        COUNT(*)             AS orders,
        SUM(o.item_total)    AS revenue,
        SUM(o.freight_total) AS freight
    FROM dw.fct_order AS o
    INNER JOIN dw.dim_date AS d
        ON d.date_key = o.purchase_date_key
    WHERE o.is_revenue = 1
      AND d.in_analysis_window = 1
    GROUP BY d.month_start, d.year_month
)
SELECT
    year_month,
    orders,
    revenue,
    CAST(revenue / orders AS DECIMAL(10, 2))                          AS avg_order_value,
    CAST(100.0 * freight / (revenue + freight) AS DECIMAL(5, 1))      AS freight_pct,
    -- LAG reads the previous month's value, so growth needs no self-join
    CAST(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month_start))
         / LAG(revenue) OVER (ORDER BY month_start) AS DECIMAL(6, 1)) AS revenue_growth_pct,
    SUM(revenue) OVER (ORDER BY month_start ROWS UNBOUNDED PRECEDING) AS cumulative_revenue
FROM monthly
ORDER BY month_start;

-- 2. Growth: Jan-Aug 2018 against Jan-Aug 2017. Revenue = orders x average order value,
-- so comparing the two shows whether growth came from more orders or bigger orders.
WITH by_year AS (
    SELECT
        d.[year],
        COUNT(*)                  AS orders,
        SUM(o.item_total)         AS revenue,
        SUM(o.item_total) / COUNT(*) AS avg_order_value
    FROM dw.fct_order AS o
    INNER JOIN dw.dim_date AS d
        ON d.date_key = o.purchase_date_key
    WHERE o.is_revenue = 1
      AND d.in_analysis_window = 1
      AND d.[month] <= 8          -- same eight months in both years
    GROUP BY d.[year]
)
SELECT
    cur.orders                                                                   AS orders_2018,
    prev.orders                                                                  AS orders_2017,
    CAST(100.0 * (cur.orders - prev.orders) / prev.orders AS DECIMAL(6, 1))      AS orders_growth_pct,
    CAST(cur.avg_order_value AS DECIMAL(10, 2))                                  AS aov_2018,
    CAST(prev.avg_order_value AS DECIMAL(10, 2))                                 AS aov_2017,
    CAST(100.0 * (cur.avg_order_value - prev.avg_order_value) / prev.avg_order_value AS DECIMAL(6, 1)) AS aov_growth_pct,
    CAST(100.0 * (cur.revenue - prev.revenue) / prev.revenue AS DECIMAL(6, 1))   AS revenue_growth_pct
FROM by_year AS cur
INNER JOIN by_year AS prev
    ON prev.[year] = cur.[year] - 1;

-- 3. The busiest days: which single days stand out?
SELECT TOP (5)
    d.full_date,
    d.day_name,
    COUNT(*)          AS orders,
    SUM(o.item_total) AS revenue
FROM dw.fct_order AS o
INNER JOIN dw.dim_date AS d
    ON d.date_key = o.purchase_date_key
WHERE o.is_revenue = 1
GROUP BY d.full_date, d.day_name
ORDER BY revenue DESC;

-- 4. Where revenue comes from: customer state, with the freight share customers pay there.
-- The customer's state at the time of the order comes from the customer history (decision 5).
WITH by_state AS (
    SELECT
        c.[state],
        COUNT(*)             AS orders,
        SUM(o.item_total)    AS revenue,
        SUM(o.freight_total) AS freight
    FROM dw.fct_order AS o
    INNER JOIN dw.dim_customer AS c
        ON c.customer_key = o.customer_key
    INNER JOIN dw.dim_date AS d
        ON d.date_key = o.purchase_date_key
    WHERE o.is_revenue = 1
      AND d.in_analysis_window = 1
    GROUP BY c.[state]
)
SELECT
    [state],
    orders,
    revenue,
    CAST(100.0 * revenue / SUM(revenue) OVER () AS DECIMAL(5, 1))                     AS pct_of_revenue,
    CAST(100.0 * SUM(revenue) OVER (ORDER BY revenue DESC ROWS UNBOUNDED PRECEDING)
         / SUM(revenue) OVER () AS DECIMAL(5, 1))                                     AS cumulative_pct,
    CAST(revenue / orders AS DECIMAL(10, 2))                                          AS avg_order_value,
    CAST(100.0 * freight / (revenue + freight) AS DECIMAL(5, 1))                      AS freight_pct
FROM by_state
ORDER BY revenue DESC;
