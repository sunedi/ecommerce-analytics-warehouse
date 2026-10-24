/*
dw.usp_load_warehouse

Rebuilds the star schema from staging. Each decision in docs/assumptions.md is
applied in exactly one place in this procedure, marked "Decision n".

Order matters: dimensions first, then fct_order, then the facts that reference it.
Everything runs in one transaction, so the warehouse is never half-built.

Surrogate keys come from ROW_NUMBER() over the natural key, so a rebuild from the
same data always produces the same keys.

Example:
    EXEC dw.usp_load_warehouse;
*/
USE EcommerceDW;
GO

CREATE OR ALTER PROCEDURE dw.usp_load_warehouse
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    -- Facts are emptied before the dimensions they reference
    DELETE FROM dw.fct_review;
    DELETE FROM dw.fct_payment;
    DELETE FROM dw.fct_order_item;
    DELETE FROM dw.fct_order;
    DELETE FROM dw.dim_customer;
    DELETE FROM dw.dim_product;
    DELETE FROM dw.dim_seller;
    DELETE FROM dw.dim_date;

    /* ---------------------------------------------------------------------
       dim_date: every day from 1 January of the first order's year to
       31 December of the year of the latest date in the data
       --------------------------------------------------------------------- */
    DECLARE @first_date DATE = (SELECT DATEFROMPARTS(YEAR(MIN(order_purchase_timestamp)), 1, 1) FROM stg.orders);
    DECLARE @last_date  DATE = (
        SELECT DATEFROMPARTS(YEAR(MAX(latest)), 12, 31)
        FROM (
            SELECT MAX(order_estimated_delivery_date) AS latest FROM stg.orders
            UNION ALL SELECT MAX(CAST(order_delivered_customer_date AS DATE)) FROM stg.orders
            UNION ALL SELECT MAX(CAST(review_creation_date AS DATE)) FROM stg.order_reviews
        ) AS latest_dates
    );

    -- A recursive CTE: the first row is @first_date, and each pass adds the next day
    WITH dates AS (
        SELECT @first_date AS full_date
        UNION ALL
        SELECT DATEADD(DAY, 1, full_date) FROM dates WHERE full_date < @last_date
    )
    INSERT INTO dw.dim_date (date_key, full_date, [year], [quarter], [month], month_name, year_month, month_start,
                             day_of_month, day_of_week, day_name, is_weekend, in_analysis_window)
    SELECT
        CONVERT(INT, CONVERT(CHAR(8), full_date, 112)),     -- style 112 is yyyymmdd
        full_date,
        YEAR(full_date),
        DATEPART(QUARTER, full_date),
        MONTH(full_date),
        FORMAT(full_date, 'MMMM', 'en-GB'),                 -- a fixed culture, so names don't depend on server language
        FORMAT(full_date, 'yyyy-MM'),
        DATEFROMPARTS(YEAR(full_date), MONTH(full_date), 1),
        DAY(full_date),
        DATEDIFF(DAY, '19000101', full_date) % 7 + 1,       -- 1 Jan 1900 was a Monday; independent of SET DATEFIRST
        FORMAT(full_date, 'dddd', 'en-GB'),
        CASE WHEN DATEDIFF(DAY, '19000101', full_date) % 7 + 1 >= 6 THEN 1 ELSE 0 END,
        -- Decision 3: monthly trends use the complete months only
        CASE WHEN full_date BETWEEN '2017-01-01' AND '2018-08-31' THEN 1 ELSE 0 END
    FROM dates
    OPTION (MAXRECURSION 0);  -- the default limit is 100 levels, about three months of days

    PRINT CONCAT('dw.dim_date: ', @@ROWCOUNT, ' rows');

    /* ---------------------------------------------------------------------
       Decision 9: one location per ZIP prefix, the average of its points
       inside Brazil. Used for customer and seller coordinates.
       --------------------------------------------------------------------- */
    DROP TABLE IF EXISTS #zip_location;

    SELECT
        geolocation_zip_code_prefix AS zip_code_prefix,
        AVG(geolocation_lat)        AS latitude,
        AVG(geolocation_lng)        AS longitude
    INTO #zip_location
    FROM stg.geolocation
    WHERE geolocation_lat BETWEEN -33.8 AND 5.3
      AND geolocation_lng BETWEEN -74.0 AND -34.8
    GROUP BY geolocation_zip_code_prefix;

    /* ---------------------------------------------------------------------
       dim_customer, decision 5: a new version each time a customer orders
       from a different location (ZIP prefix, city or state).

       This is a "gaps and islands" problem. Ordered by purchase time, each
       customer's orders form runs (islands) of the same location:
         1. LAG compares each order's location with the previous order's.
         2. A running SUM of "location changed" flags numbers the islands.
       A customer who moves A -> B -> A gets three versions, which grouping
       by location alone would merge into two.
       --------------------------------------------------------------------- */
    WITH customer_orders AS (
        SELECT c.customer_unique_id, c.customer_id, c.customer_zip_code_prefix, c.customer_city, c.customer_state,
               o.order_purchase_timestamp
        FROM stg.customers AS c
        INNER JOIN stg.orders AS o
            ON o.customer_id = c.customer_id
    ),
    location_changes AS (
        SELECT
            *,
            -- 1 for a customer's first order (LAG is NULL) and whenever the location differs from the previous order
            CASE
                WHEN LAG(customer_zip_code_prefix) OVER (PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp, customer_id) = customer_zip_code_prefix
                 AND LAG(customer_city)            OVER (PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp, customer_id) = customer_city
                 AND LAG(customer_state)           OVER (PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp, customer_id) = customer_state
                THEN 0
                ELSE 1
            END AS is_new_location
        FROM customer_orders
    ),
    numbered AS (
        SELECT
            *,
            SUM(is_new_location) OVER (PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp, customer_id
                                       ROWS UNBOUNDED PRECEDING) AS version_number
        FROM location_changes
    ),
    versions AS (
        SELECT customer_unique_id, version_number, customer_zip_code_prefix, customer_city, customer_state,
               MIN(order_purchase_timestamp) AS valid_from
        FROM numbered
        GROUP BY customer_unique_id, version_number, customer_zip_code_prefix, customer_city, customer_state
    )
    INSERT INTO dw.dim_customer (customer_key, customer_unique_id, version_number, zip_code_prefix, city, [state],
                                 latitude, longitude, valid_from, valid_to, is_current)
    SELECT
        ROW_NUMBER() OVER (ORDER BY v.customer_unique_id, v.version_number),
        v.customer_unique_id,
        v.version_number,
        v.customer_zip_code_prefix,
        v.customer_city,
        v.customer_state,
        z.latitude,
        z.longitude,
        v.valid_from,
        -- Each version ends where the next one starts; the latest version is open-ended
        LEAD(v.valid_from, 1, '9999-12-31 23:59:59') OVER (PARTITION BY v.customer_unique_id ORDER BY v.version_number),
        CASE WHEN LEAD(v.valid_from) OVER (PARTITION BY v.customer_unique_id ORDER BY v.version_number) IS NULL THEN 1 ELSE 0 END
    FROM versions AS v
    LEFT JOIN #zip_location AS z
        ON z.zip_code_prefix = v.customer_zip_code_prefix;

    PRINT CONCAT('dw.dim_customer: ', @@ROWCOUNT, ' rows');

    /* ---------------------------------------------------------------------
       dim_product, decision 8: English category names, two translations
       added here, and 'unknown' for products without a category.
       A category with no translation would leave category_name NULL, which
       the NOT NULL column rejects, so a new untranslated category stops the load.
       --------------------------------------------------------------------- */
    WITH translations AS (
        SELECT product_category_name, product_category_name_english
        FROM stg.category_translation
        UNION ALL
        SELECT product_category_name, product_category_name_english
        FROM (VALUES
            (N'pc_gamer',                                      N'pc_gamer'),
            (N'portateis_cozinha_e_preparadores_de_alimentos', N'portable_kitchen_and_food_preparers')
        ) AS missing_from_source (product_category_name, product_category_name_english)
    )
    INSERT INTO dw.dim_product (product_key, product_id, category_name, category_name_portuguese, name_length,
                                description_length, photos_qty, weight_g, length_cm, height_cm, width_cm)
    SELECT
        ROW_NUMBER() OVER (ORDER BY p.product_id),
        p.product_id,
        CASE WHEN p.product_category_name IS NULL THEN N'unknown' ELSE t.product_category_name_english END,
        p.product_category_name,
        p.product_name_length,
        p.product_description_length,
        p.product_photos_qty,
        p.product_weight_g,
        p.product_length_cm,
        p.product_height_cm,
        p.product_width_cm
    FROM stg.products AS p
    LEFT JOIN translations AS t
        ON t.product_category_name = p.product_category_name;

    PRINT CONCAT('dw.dim_product: ', @@ROWCOUNT, ' rows');

    /* ---------------------------------------------------------------------
       dim_seller
       --------------------------------------------------------------------- */
    INSERT INTO dw.dim_seller (seller_key, seller_id, zip_code_prefix, city, [state], latitude, longitude)
    SELECT
        ROW_NUMBER() OVER (ORDER BY s.seller_id),
        s.seller_id,
        s.seller_zip_code_prefix,
        s.seller_city,
        s.seller_state,
        z.latitude,
        z.longitude
    FROM stg.sellers AS s
    LEFT JOIN #zip_location AS z
        ON z.zip_code_prefix = s.seller_zip_code_prefix;

    PRINT CONCAT('dw.dim_seller: ', @@ROWCOUNT, ' rows');

    /* ---------------------------------------------------------------------
       Decision 6: rank each order's reviews; the most recently answered one
       gives the order its score. Used by both fct_order and fct_review.
       --------------------------------------------------------------------- */
    DROP TABLE IF EXISTS #reviews;

    SELECT
        review_id,
        order_id,
        review_score,
        review_comment_title,
        review_comment_message,
        review_creation_date,
        review_answer_timestamp,
        CASE
            WHEN ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_answer_timestamp DESC, review_id) = 1 THEN 1
            ELSE 0
        END AS is_latest_for_order
    INTO #reviews
    FROM stg.order_reviews;

    /* ---------------------------------------------------------------------
       fct_order: one row per order. Items, payments and reviews are each
       summed to one row per order BEFORE joining, so no total is repeated.
       --------------------------------------------------------------------- */
    WITH items AS (
        SELECT order_id,
               COUNT(*)                  AS item_count,
               COUNT(DISTINCT seller_id) AS seller_count,
               SUM(price)                AS item_total,
               SUM(freight_value)        AS freight_total
        FROM stg.order_items
        GROUP BY order_id
    ),
    payments AS (
        SELECT order_id,
               COUNT(*)           AS payment_count,
               SUM(payment_value) AS payment_total
        FROM stg.order_payments
        GROUP BY order_id
    ),
    reviews AS (
        SELECT order_id,
               COUNT(*)                                                 AS review_count,
               MAX(CASE WHEN is_latest_for_order = 1 THEN review_score END) AS review_score
        FROM #reviews
        GROUP BY order_id
    )
    INSERT INTO dw.fct_order (order_id, customer_key, purchase_date_key, delivered_date_key, estimated_delivery_date_key,
                              order_status, is_revenue, purchase_timestamp, approved_at, delivered_to_carrier_at,
                              delivered_to_customer_at, estimated_delivery_date, item_count, seller_count, item_total,
                              freight_total, payment_count, payment_total, delivery_days, days_late, is_late,
                              review_count, review_score)
    SELECT
        o.order_id,
        dc.customer_key,
        CONVERT(INT, CONVERT(CHAR(8), o.order_purchase_timestamp, 112)),
        CONVERT(INT, CONVERT(CHAR(8), o.order_delivered_customer_date, 112)),
        CONVERT(INT, CONVERT(CHAR(8), o.order_estimated_delivery_date, 112)),
        o.order_status,
        -- Decision 2: revenue counts delivered orders only
        CASE WHEN o.order_status = 'delivered' THEN 1 ELSE 0 END,
        o.order_purchase_timestamp,
        o.order_approved_at,
        o.order_delivered_carrier_date,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date,
        ISNULL(i.item_count, 0),
        ISNULL(i.seller_count, 0),
        ISNULL(i.item_total, 0),
        ISNULL(i.freight_total, 0),
        ISNULL(p.payment_count, 0),
        ISNULL(p.payment_total, 0),
        -- Decision 10: delivery time is purchase to delivered to customer only
        CAST(DATEDIFF(SECOND, o.order_purchase_timestamp, o.order_delivered_customer_date) / 86400.0 AS DECIMAL(6, 2)),
        DATEDIFF(DAY, o.order_estimated_delivery_date, CAST(o.order_delivered_customer_date AS DATE)),
        CASE
            WHEN o.order_delivered_customer_date IS NULL THEN NULL
            WHEN CAST(o.order_delivered_customer_date AS DATE) > o.order_estimated_delivery_date THEN 1
            ELSE 0
        END,
        ISNULL(r.review_count, 0),
        r.review_score
    FROM stg.orders AS o
    INNER JOIN stg.customers AS c
        ON c.customer_id = o.customer_id
    -- Slowly changing dimension lookup: the customer version that was valid when the order was placed
    INNER JOIN dw.dim_customer AS dc
        ON  dc.customer_unique_id = c.customer_unique_id
        AND o.order_purchase_timestamp >= dc.valid_from
        AND o.order_purchase_timestamp <  dc.valid_to
    LEFT JOIN items    AS i ON i.order_id = o.order_id
    LEFT JOIN payments AS p ON p.order_id = o.order_id
    LEFT JOIN reviews  AS r ON r.order_id = o.order_id;

    PRINT CONCAT('dw.fct_order: ', @@ROWCOUNT, ' rows');

    /* ---------------------------------------------------------------------
       fct_order_item, fct_payment, fct_review: order-level attributes
       (customer, purchase date, status) come from fct_order, so they are
       decided once and agree everywhere.
       --------------------------------------------------------------------- */
    INSERT INTO dw.fct_order_item (order_id, order_item_id, product_key, seller_key, customer_key, purchase_date_key,
                                   order_status, is_revenue, shipping_limit_at, price, freight_value)
    SELECT
        i.order_id,
        i.order_item_id,
        dp.product_key,
        ds.seller_key,
        fo.customer_key,
        fo.purchase_date_key,
        fo.order_status,
        fo.is_revenue,
        i.shipping_limit_date,
        i.price,
        i.freight_value
    FROM stg.order_items AS i
    INNER JOIN dw.fct_order   AS fo ON fo.order_id   = i.order_id
    INNER JOIN dw.dim_product AS dp ON dp.product_id = i.product_id
    INNER JOIN dw.dim_seller  AS ds ON ds.seller_id  = i.seller_id;

    PRINT CONCAT('dw.fct_order_item: ', @@ROWCOUNT, ' rows');

    INSERT INTO dw.fct_payment (order_id, payment_sequential, customer_key, purchase_date_key, payment_type,
                                payment_installments, payment_value)
    SELECT
        p.order_id,
        p.payment_sequential,
        fo.customer_key,
        fo.purchase_date_key,
        p.payment_type,
        p.payment_installments,
        p.payment_value
    FROM stg.order_payments AS p
    INNER JOIN dw.fct_order AS fo
        ON fo.order_id = p.order_id;

    PRINT CONCAT('dw.fct_payment: ', @@ROWCOUNT, ' rows');

    INSERT INTO dw.fct_review (review_id, order_id, customer_key, created_date_key, review_score, has_comment,
                               comment_title, comment_message, created_at, answered_at, is_latest_for_order)
    SELECT
        r.review_id,
        r.order_id,
        fo.customer_key,
        CONVERT(INT, CONVERT(CHAR(8), r.review_creation_date, 112)),
        r.review_score,
        CASE WHEN r.review_comment_title IS NOT NULL OR r.review_comment_message IS NOT NULL THEN 1 ELSE 0 END,
        r.review_comment_title,
        r.review_comment_message,
        r.review_creation_date,
        r.review_answer_timestamp,
        r.is_latest_for_order
    FROM #reviews AS r
    INNER JOIN dw.fct_order AS fo
        ON fo.order_id = r.order_id;

    PRINT CONCAT('dw.fct_review: ', @@ROWCOUNT, ' rows');

    COMMIT;
END;
GO
