/*
Reference figures for checking the Power BI dashboard.

Each section calculates, from the marts, exactly what a dashboard page should show,
using the same formulas as the DAX measures (sums divided by counts, never averages
of averages). If a dashboard figure differs from this output, the dashboard is wrong:
usually a missing filter or a measure that averages a ratio column.
*/
USE EcommerceDW;
GO

-- 1. Executive page: KPI cards, filtered to the analysis window (Jan 2017 - Aug 2018)
SELECT
    SUM(revenue)                                                                     AS revenue,
    SUM(delivered_orders)                                                            AS delivered_orders,
    CAST(SUM(revenue) / SUM(delivered_orders) AS DECIMAL(10, 2))                     AS avg_order_value,
    CAST(100.0 * SUM(freight) / (SUM(revenue) + SUM(freight)) AS DECIMAL(5, 1))      AS freight_share_pct,
    CAST(100.0 * SUM(late_orders) / SUM(delivered_with_date) AS DECIMAL(5, 1))       AS late_rate_pct,
    CAST(SUM(delivery_days_sum) / SUM(delivered_with_date) AS DECIMAL(5, 1))         AS avg_delivery_days,
    CAST(1.0 * SUM(review_score_sum) / SUM(reviewed_orders) AS DECIMAL(3, 2))        AS avg_review_score,
    SUM(new_customers)                                                               AS new_customers
FROM mart.monthly_performance
WHERE in_analysis_window = 1;

-- 1b. Executive page with a year filter. 2017 covers 12 months and 2018 only 8 (Jan - Aug),
-- so yearly totals are not comparable; ratios such as average order value and late rate are.
SELECT
    YEAR(month_start)                                                                AS [year],
    COUNT(*)                                                                         AS months,
    SUM(revenue)                                                                     AS revenue,
    SUM(delivered_orders)                                                            AS delivered_orders,
    CAST(SUM(revenue) / SUM(delivered_orders) AS DECIMAL(10, 2))                     AS avg_order_value,
    CAST(100.0 * SUM(freight) / (SUM(revenue) + SUM(freight)) AS DECIMAL(5, 1))      AS freight_share_pct,
    CAST(100.0 * SUM(late_orders) / SUM(delivered_with_date) AS DECIMAL(5, 1))       AS late_rate_pct,
    CAST(SUM(delivery_days_sum) / SUM(delivered_with_date) AS DECIMAL(5, 1))         AS avg_delivery_days,
    CAST(1.0 * SUM(review_score_sum) / SUM(reviewed_orders) AS DECIMAL(3, 2))        AS avg_review_score
FROM mart.monthly_performance
WHERE in_analysis_window = 1
GROUP BY YEAR(month_start)
ORDER BY [year];

-- 2. Delivery page: review score by arrival
SELECT arrival, orders, avg_review_score, one_star_pct
FROM mart.delivery_review
ORDER BY sort_order;

-- 3. Delivery page: states, slowest first (analysis window)
SELECT
    [state],
    state_name,
    region,
    SUM(delivered_orders)                                                      AS delivered_orders,
    CAST(SUM(delivery_days_sum) / SUM(delivered_with_date) AS DECIMAL(5, 1))   AS avg_delivery_days,
    CAST(100.0 * SUM(late_orders) / SUM(delivered_with_date) AS DECIMAL(5, 1)) AS late_rate_pct
FROM mart.state_monthly
WHERE in_analysis_window = 1
GROUP BY [state], state_name, region
ORDER BY avg_delivery_days DESC;

-- 4. Categories page: top 5 by revenue, and office furniture (analysis window)
SELECT TOP (5)
    category_name,
    SUM(revenue)                                                                       AS revenue,
    CAST(1.0 * SUM(review_score_sum) / SUM(reviewed_orders) AS DECIMAL(3, 2))          AS avg_review_score,
    CAST(1.0 * SUM(on_time_review_score_sum) / SUM(on_time_reviewed_orders) AS DECIMAL(3, 2)) AS on_time_review_score
FROM mart.category_monthly
WHERE in_analysis_window = 1
GROUP BY category_name
ORDER BY revenue DESC;

SELECT
    category_name,
    CAST(1.0 * SUM(review_score_sum) / SUM(reviewed_orders) AS DECIMAL(3, 2))          AS avg_review_score,
    CAST(1.0 * SUM(on_time_review_score_sum) / SUM(on_time_reviewed_orders) AS DECIMAL(3, 2)) AS on_time_review_score
FROM mart.category_monthly
WHERE in_analysis_window = 1
  AND category_name = N'office_furniture'
GROUP BY category_name;

-- 5. Sellers page: late rate by decile (all time, sellers with 50+ single-seller orders)
SELECT
    late_rate_decile,
    COUNT(*)                                                                    AS sellers,
    CAST(100.0 * SUM(late_orders) / SUM(single_seller_orders) AS DECIMAL(5, 1)) AS late_rate_pct
FROM mart.seller_performance
WHERE late_rate_decile IS NOT NULL
GROUP BY late_rate_decile
ORDER BY late_rate_decile;

-- 6. Customers page (all time): customers with at least one delivered order
SELECT
    COUNT(*)                                                               AS customers,
    SUM(CAST(is_repeat AS INT))                                            AS repeat_customers,
    CAST(100.0 * SUM(CAST(is_repeat AS INT)) / COUNT(*) AS DECIMAL(5, 1))  AS repeat_rate_pct,
    SUM(CAST(second_order_same_day AS INT))                                AS second_order_same_day
FROM mart.customer_summary
WHERE delivered_orders > 0;
