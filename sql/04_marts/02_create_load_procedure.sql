/*
mart.usp_load_marts

Rebuilds every mart from the star schema in one transaction. Marts read only from dw,
never from staging, so they always agree with the warehouse.

Definitions match the analysis queries in queries/, so the dashboard and the executive
summary show the same numbers.

Example:
    EXEC mart.usp_load_marts;
*/
USE EcommerceDW;
GO

CREATE OR ALTER PROCEDURE mart.usp_load_marts
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Brazilian states with their regions (IBGE). Names are written without accents so the
    -- SQL files stay plain ASCII and read correctly in sqlcmd and SSMS.
    DROP TABLE IF EXISTS #states;

    SELECT [state], state_name, region
    INTO #states
    FROM (VALUES
        ('AC', 'Acre',                'North'),        ('AL', 'Alagoas',             'Northeast'),
        ('AM', 'Amazonas',            'North'),        ('AP', 'Amapa',               'North'),
        ('BA', 'Bahia',               'Northeast'),    ('CE', 'Ceara',               'Northeast'),
        ('DF', 'Distrito Federal',    'Central-West'), ('ES', 'Espirito Santo',      'Southeast'),
        ('GO', 'Goias',               'Central-West'), ('MA', 'Maranhao',            'Northeast'),
        ('MG', 'Minas Gerais',        'Southeast'),    ('MS', 'Mato Grosso do Sul',  'Central-West'),
        ('MT', 'Mato Grosso',         'Central-West'), ('PA', 'Para',                'North'),
        ('PB', 'Paraiba',             'Northeast'),    ('PE', 'Pernambuco',          'Northeast'),
        ('PI', 'Piaui',               'Northeast'),    ('PR', 'Parana',              'South'),
        ('RJ', 'Rio de Janeiro',      'Southeast'),    ('RN', 'Rio Grande do Norte', 'Northeast'),
        ('RO', 'Rondonia',            'North'),        ('RR', 'Roraima',             'North'),
        ('RS', 'Rio Grande do Sul',   'South'),        ('SC', 'Santa Catarina',      'South'),
        ('SE', 'Sergipe',             'Northeast'),    ('SP', 'Sao Paulo',           'Southeast'),
        ('TO', 'Tocantins',           'North')
    ) AS s ([state], state_name, region);

    -- One row per month with its analysis-window flag (constant within a month)
    DROP TABLE IF EXISTS #months;

    SELECT month_start, MAX(year_month) AS year_month, MAX(CAST(in_analysis_window AS INT)) AS in_analysis_window
    INTO #months
    FROM dw.dim_date
    GROUP BY month_start;

    BEGIN TRANSACTION;

    /* ---------------------------------------------------------------------
       monthly_performance: one row per purchase month
       --------------------------------------------------------------------- */
    TRUNCATE TABLE mart.monthly_performance;

    WITH orders AS (
        SELECT
            o.order_id,
            o.is_revenue,
            o.item_total,
            o.freight_total,
            o.is_late,
            o.delivery_days,
            o.review_score,
            c.customer_unique_id,
            d.month_start,
            -- 1 for each customer's first delivered order; order_id breaks ties between
            -- orders placed at the same second, so a customer is new only once
            CASE
                WHEN o.is_revenue = 1
                 AND ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id, o.is_revenue
                                        ORDER BY o.purchase_timestamp, o.order_id) = 1
                THEN 1 ELSE 0
            END AS is_first_delivered_order
        FROM dw.fct_order AS o
        INNER JOIN dw.dim_customer AS c
            ON c.customer_key = o.customer_key
        INNER JOIN dw.dim_date AS d
            ON d.date_key = o.purchase_date_key
    ),
    monthly AS (
        SELECT
            month_start,
            COUNT(*)                                                                AS orders,
            SUM(CAST(is_revenue AS INT))                                            AS delivered_orders,
            SUM(CASE WHEN is_revenue = 1 THEN item_total ELSE 0 END)                AS revenue,
            SUM(CASE WHEN is_revenue = 1 THEN freight_total ELSE 0 END)             AS freight,
            COUNT(DISTINCT CASE WHEN is_revenue = 1 THEN customer_unique_id END)    AS customers,
            SUM(is_first_delivered_order)                                           AS new_customers,
            SUM(CASE WHEN is_revenue = 1 AND is_late IS NOT NULL THEN 1 ELSE 0 END) AS delivered_with_date,
            SUM(CASE WHEN is_revenue = 1 AND is_late = 1 THEN 1 ELSE 0 END)         AS late_orders,
            ISNULL(SUM(CASE WHEN is_revenue = 1 THEN delivery_days END), 0)         AS delivery_days_sum,
            SUM(CASE WHEN is_revenue = 1 AND review_score IS NOT NULL THEN 1 ELSE 0 END) AS reviewed_orders,
            ISNULL(SUM(CASE WHEN is_revenue = 1 THEN review_score END), 0)          AS review_score_sum,
            SUM(CASE WHEN is_revenue = 1 AND review_score = 1 THEN 1 ELSE 0 END)    AS one_star_orders
        FROM orders
        GROUP BY month_start
    )
    INSERT INTO mart.monthly_performance (month_start, year_month, in_analysis_window, orders, delivered_orders,
        revenue, freight, customers, new_customers, delivered_with_date, late_orders, delivery_days_sum,
        reviewed_orders, review_score_sum, one_star_orders, avg_order_value, freight_pct, late_pct,
        avg_delivery_days, avg_review_score)
    SELECT
        m.month_start,
        mo.year_month,
        mo.in_analysis_window,
        m.orders,
        m.delivered_orders,
        m.revenue,
        m.freight,
        m.customers,
        m.new_customers,
        m.delivered_with_date,
        m.late_orders,
        m.delivery_days_sum,
        m.reviewed_orders,
        m.review_score_sum,
        m.one_star_orders,
        m.revenue / NULLIF(m.delivered_orders, 0),
        100.0 * m.freight / NULLIF(m.revenue + m.freight, 0),
        100.0 * m.late_orders / NULLIF(m.delivered_with_date, 0),
        m.delivery_days_sum / NULLIF(m.delivered_with_date, 0),
        1.0 * m.review_score_sum / NULLIF(m.reviewed_orders, 0)
    FROM monthly AS m
    INNER JOIN #months AS mo
        ON mo.month_start = m.month_start;

    PRINT CONCAT('mart.monthly_performance: ', @@ROWCOUNT, ' rows');

    /* ---------------------------------------------------------------------
       state_monthly: delivered orders by month and the customer's state
       at the time of the order
       --------------------------------------------------------------------- */
    TRUNCATE TABLE mart.state_monthly;

    INSERT INTO mart.state_monthly (month_start, [state], state_name, region, in_analysis_window, delivered_orders,
        revenue, freight, delivered_with_date, late_orders, delivery_days_sum, reviewed_orders, review_score_sum)
    SELECT
        d.month_start,
        c.[state],
        s.state_name,
        s.region,
        MAX(CAST(d.in_analysis_window AS INT)),
        COUNT(*),
        SUM(o.item_total),
        SUM(o.freight_total),
        SUM(CASE WHEN o.is_late IS NOT NULL THEN 1 ELSE 0 END),
        SUM(CASE WHEN o.is_late = 1 THEN 1 ELSE 0 END),
        ISNULL(SUM(o.delivery_days), 0),
        SUM(CASE WHEN o.review_score IS NOT NULL THEN 1 ELSE 0 END),
        ISNULL(SUM(o.review_score), 0)
    FROM dw.fct_order AS o
    INNER JOIN dw.dim_customer AS c
        ON c.customer_key = o.customer_key
    INNER JOIN dw.dim_date AS d
        ON d.date_key = o.purchase_date_key
    INNER JOIN #states AS s
        ON s.[state] = c.[state]
    WHERE o.is_revenue = 1
    GROUP BY d.month_start, c.[state], s.state_name, s.region;

    PRINT CONCAT('mart.state_monthly: ', @@ROWCOUNT, ' rows');

    /* ---------------------------------------------------------------------
       category_monthly: item measures come from item rows; order measures
       (lateness, reviews) from one row per order and category, so an order
       with three items in one category counts once
       --------------------------------------------------------------------- */
    TRUNCATE TABLE mart.category_monthly;

    WITH item_level AS (
        SELECT d.month_start, p.category_name, COUNT(*) AS items, SUM(i.price) AS revenue
        FROM dw.fct_order_item AS i
        INNER JOIN dw.dim_product AS p ON p.product_key = i.product_key
        INNER JOIN dw.dim_date    AS d ON d.date_key    = i.purchase_date_key
        WHERE i.is_revenue = 1
        GROUP BY d.month_start, p.category_name
    ),
    order_categories AS (
        SELECT DISTINCT d.month_start, p.category_name, i.order_id
        FROM dw.fct_order_item AS i
        INNER JOIN dw.dim_product AS p ON p.product_key = i.product_key
        INNER JOIN dw.dim_date    AS d ON d.date_key    = i.purchase_date_key
        WHERE i.is_revenue = 1
    ),
    order_level AS (
        SELECT
            oc.month_start,
            oc.category_name,
            COUNT(*)                                                                     AS orders,
            SUM(CASE WHEN o.is_late IS NOT NULL THEN 1 ELSE 0 END)                       AS delivered_with_date,
            SUM(CASE WHEN o.is_late = 1 THEN 1 ELSE 0 END)                               AS late_orders,
            SUM(CASE WHEN o.review_score IS NOT NULL THEN 1 ELSE 0 END)                  AS reviewed_orders,
            ISNULL(SUM(o.review_score), 0)                                               AS review_score_sum,
            SUM(CASE WHEN o.review_score = 1 THEN 1 ELSE 0 END)                          AS one_star_orders,
            SUM(CASE WHEN o.is_late = 0 AND o.review_score IS NOT NULL THEN 1 ELSE 0 END) AS on_time_reviewed_orders,
            ISNULL(SUM(CASE WHEN o.is_late = 0 THEN o.review_score END), 0)              AS on_time_review_score_sum
        FROM order_categories AS oc
        INNER JOIN dw.fct_order AS o
            ON o.order_id = oc.order_id
        GROUP BY oc.month_start, oc.category_name
    )
    INSERT INTO mart.category_monthly (month_start, category_name, in_analysis_window, orders, items, revenue,
        delivered_with_date, late_orders, reviewed_orders, review_score_sum, one_star_orders,
        on_time_reviewed_orders, on_time_review_score_sum)
    SELECT
        il.month_start,
        il.category_name,
        mo.in_analysis_window,
        ol.orders,
        il.items,
        il.revenue,
        ol.delivered_with_date,
        ol.late_orders,
        ol.reviewed_orders,
        ol.review_score_sum,
        ol.one_star_orders,
        ol.on_time_reviewed_orders,
        ol.on_time_review_score_sum
    FROM item_level AS il
    INNER JOIN order_level AS ol
        ON ol.month_start = il.month_start AND ol.category_name = il.category_name
    INNER JOIN #months AS mo
        ON mo.month_start = il.month_start;

    PRINT CONCAT('mart.category_monthly: ', @@ROWCOUNT, ' rows');

    /* ---------------------------------------------------------------------
       seller_performance: one row per seller, including sellers with no
       delivered sales
       --------------------------------------------------------------------- */
    TRUNCATE TABLE mart.seller_performance;

    WITH sales AS (
        SELECT
            i.seller_key,
            COUNT(DISTINCT i.order_id) AS delivered_orders,
            COUNT(*)                   AS items_sold,
            SUM(i.price)               AS revenue,
            SUM(i.freight_value)       AS freight,
            MIN(d.full_date)           AS first_sale_date,
            MAX(d.full_date)           AS last_sale_date
        FROM dw.fct_order_item AS i
        INNER JOIN dw.dim_date AS d
            ON d.date_key = i.purchase_date_key
        WHERE i.is_revenue = 1
        GROUP BY i.seller_key
    ),
    -- Same rules as queries/03_delivery_and_reviews.sql: delivered single-seller orders with a delivery date
    single_seller_orders AS (
        SELECT DISTINCT i.seller_key, o.order_id, o.is_late, o.delivery_days, o.review_score
        FROM dw.fct_order_item AS i
        INNER JOIN dw.fct_order AS o
            ON o.order_id = i.order_id
        WHERE o.is_revenue = 1
          AND o.seller_count = 1
          AND o.is_late IS NOT NULL
    ),
    delivery AS (
        SELECT
            seller_key,
            COUNT(*)                                                    AS single_seller_orders,
            SUM(CAST(is_late AS INT))                                   AS late_orders,
            SUM(delivery_days)                                          AS delivery_days_sum,
            SUM(CASE WHEN review_score IS NOT NULL THEN 1 ELSE 0 END)   AS reviewed_orders,
            ISNULL(SUM(review_score), 0)                                AS review_score_sum
        FROM single_seller_orders
        GROUP BY seller_key
    ),
    deciles AS (
        SELECT
            seller_key,
            NTILE(10) OVER (ORDER BY 1.0 * late_orders / single_seller_orders DESC, seller_key) AS late_rate_decile
        FROM delivery
        WHERE single_seller_orders >= 50
    )
    INSERT INTO mart.seller_performance (seller_id, [state], region, latitude, longitude, first_sale_date, last_sale_date,
        delivered_orders, items_sold, revenue, freight, single_seller_orders, late_orders, delivery_days_sum,
        reviewed_orders, review_score_sum, late_pct, avg_delivery_days, avg_review_score, late_rate_decile)
    SELECT
        s.seller_id,
        s.[state],
        st.region,
        s.latitude,
        s.longitude,
        sa.first_sale_date,
        sa.last_sale_date,
        ISNULL(sa.delivered_orders, 0),
        ISNULL(sa.items_sold, 0),
        ISNULL(sa.revenue, 0),
        ISNULL(sa.freight, 0),
        ISNULL(de.single_seller_orders, 0),
        ISNULL(de.late_orders, 0),
        ISNULL(de.delivery_days_sum, 0),
        ISNULL(de.reviewed_orders, 0),
        ISNULL(de.review_score_sum, 0),
        100.0 * de.late_orders / NULLIF(de.single_seller_orders, 0),
        de.delivery_days_sum / NULLIF(de.single_seller_orders, 0),
        1.0 * de.review_score_sum / NULLIF(de.reviewed_orders, 0),
        dc.late_rate_decile
    FROM dw.dim_seller AS s
    INNER JOIN #states    AS st ON st.[state]   = s.[state]
    LEFT JOIN sales       AS sa ON sa.seller_key = s.seller_key
    LEFT JOIN delivery    AS de ON de.seller_key = s.seller_key
    LEFT JOIN deciles     AS dc ON dc.seller_key = s.seller_key;

    PRINT CONCAT('mart.seller_performance: ', @@ROWCOUNT, ' rows');

    /* ---------------------------------------------------------------------
       customer_summary: one row per customer (customer_unique_id)
       --------------------------------------------------------------------- */
    TRUNCATE TABLE mart.customer_summary;

    WITH versions AS (
        SELECT
            customer_unique_id,
            COUNT(*)                                     AS locations,
            MAX(CASE WHEN is_current = 1 THEN [state] END) AS current_state
        FROM dw.dim_customer
        GROUP BY customer_unique_id
    ),
    all_orders AS (
        SELECT c.customer_unique_id, COUNT(*) AS orders
        FROM dw.fct_order AS o
        INNER JOIN dw.dim_customer AS c
            ON c.customer_key = o.customer_key
        GROUP BY c.customer_unique_id
    ),
    delivered AS (
        SELECT
            c.customer_unique_id,
            o.purchase_timestamp,
            o.item_total,
            o.review_score,
            o.is_late,
            ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id ORDER BY o.purchase_timestamp, o.order_id) AS order_number
        FROM dw.fct_order AS o
        INNER JOIN dw.dim_customer AS c
            ON c.customer_key = o.customer_key
        WHERE o.is_revenue = 1
    ),
    delivered_summary AS (
        SELECT
            customer_unique_id,
            COUNT(*)                                                         AS delivered_orders,
            SUM(item_total)                                                  AS revenue,
            MIN(purchase_timestamp)                                          AS first_delivered_order_at,
            MAX(purchase_timestamp)                                          AS last_delivered_order_at,
            MAX(CASE WHEN order_number = 2 THEN purchase_timestamp END)      AS second_delivered_order_at,
            MAX(CASE WHEN order_number = 1 THEN review_score END)            AS first_order_review_score,
            MAX(CASE WHEN order_number = 1 THEN CAST(is_late AS INT) END)    AS first_order_was_late
        FROM delivered
        GROUP BY customer_unique_id
    )
    INSERT INTO mart.customer_summary (customer_unique_id, current_state, region, locations, orders, delivered_orders,
        revenue, first_delivered_order_at, last_delivered_order_at, is_repeat, second_order_same_day,
        days_to_second_order, first_order_review_score, first_order_was_late)
    SELECT
        v.customer_unique_id,
        v.current_state,
        st.region,
        v.locations,
        a.orders,
        ISNULL(ds.delivered_orders, 0),
        ISNULL(ds.revenue, 0),
        ds.first_delivered_order_at,
        ds.last_delivered_order_at,
        CASE WHEN ds.delivered_orders >= 2 THEN 1 ELSE 0 END,
        CASE
            WHEN ds.second_delivered_order_at IS NULL THEN NULL
            WHEN DATEDIFF(DAY, ds.first_delivered_order_at, ds.second_delivered_order_at) = 0 THEN 1
            ELSE 0
        END,
        DATEDIFF(DAY, ds.first_delivered_order_at, ds.second_delivered_order_at),
        ds.first_order_review_score,
        ds.first_order_was_late
    FROM versions AS v
    INNER JOIN #states       AS st ON st.[state] = v.current_state
    INNER JOIN all_orders    AS a  ON a.customer_unique_id  = v.customer_unique_id
    LEFT JOIN delivered_summary AS ds ON ds.customer_unique_id = v.customer_unique_id;

    PRINT CONCAT('mart.customer_summary: ', @@ROWCOUNT, ' rows');

    /* ---------------------------------------------------------------------
       delivery_review: review scores by how early or late orders arrived
       (same buckets as queries/03_delivery_and_reviews.sql)
       --------------------------------------------------------------------- */
    TRUNCATE TABLE mart.delivery_review;

    WITH bucketed AS (
        SELECT
            CASE
                WHEN days_late <= -15 THEN 1
                WHEN days_late <= -8  THEN 2
                WHEN days_late <= -1  THEN 3
                WHEN days_late = 0    THEN 4
                WHEN days_late <= 3   THEN 5
                WHEN days_late <= 7   THEN 6
                ELSE                       7
            END AS sort_order,
            review_score
        FROM dw.fct_order
        WHERE is_revenue = 1
          AND days_late IS NOT NULL
          AND review_score IS NOT NULL
    ),
    grouped AS (
        SELECT
            sort_order,
            COUNT(*)                                            AS orders,
            SUM(review_score)                                   AS review_score_sum,
            SUM(CASE WHEN review_score = 1 THEN 1 ELSE 0 END)   AS one_star_orders,
            SUM(CASE WHEN review_score = 5 THEN 1 ELSE 0 END)   AS five_star_orders
        FROM bucketed
        GROUP BY sort_order
    )
    INSERT INTO mart.delivery_review (sort_order, arrival, orders, review_score_sum, one_star_orders, five_star_orders,
        avg_review_score, one_star_pct, five_star_pct)
    SELECT
        g.sort_order,
        b.arrival,
        g.orders,
        g.review_score_sum,
        g.one_star_orders,
        g.five_star_orders,
        1.0 * g.review_score_sum / g.orders,
        100.0 * g.one_star_orders / g.orders,
        100.0 * g.five_star_orders / g.orders
    FROM grouped AS g
    INNER JOIN (VALUES
        (1, '15+ days early'), (2, '8-14 days early'), (3, '1-7 days early'), (4, 'on the estimated day'),
        (5, '1-3 days late'),  (6, '4-7 days late'),   (7, '8+ days late')
    ) AS b (sort_order, arrival)
        ON b.sort_order = g.sort_order;

    PRINT CONCAT('mart.delivery_review: ', @@ROWCOUNT, ' rows');

    COMMIT;
END;
GO
