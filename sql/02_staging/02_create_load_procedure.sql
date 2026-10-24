/*
stg.usp_load_staging

Rebuilds every staging table from its raw table: converts text to proper data
types, trims text values and corrects column names. Row for row, nothing is
filtered, deduplicated or joined.

- TRY_CONVERT returns NULL instead of failing when a value can't be converted.
  tests/02_staging_checks.sql proves no value was lost this way.
- Dates use style 120 ('yyyy-mm-dd hh:mi:ss'), so they convert the same way
  whatever the server's language or date format settings are.
- Text is trimmed of spaces, tabs and line breaks at both ends. Text that is
  empty after trimming becomes NULL.

All tables are rebuilt in one transaction, so a failure leaves staging exactly
as it was before the procedure ran.

Example:
    EXEC stg.usp_load_staging;
*/
USE EcommerceDW;
GO

CREATE OR ALTER PROCEDURE stg.usp_load_staging
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Trimmed from both ends of text values: space, tab, carriage return, line feed
    DECLARE @whitespace NVARCHAR(4) = NCHAR(32) + NCHAR(9) + NCHAR(13) + NCHAR(10);

    -- Text is compared with a binary collation (exact characters). Under the database's
    -- default collation, text made only of emoji counts as equal to '' and would be lost.
    BEGIN TRANSACTION;

    TRUNCATE TABLE stg.customers;
    INSERT INTO stg.customers (customer_id, customer_unique_id, customer_zip_code_prefix, customer_city, customer_state)
    SELECT
        customer_id,
        customer_unique_id,
        customer_zip_code_prefix,
        NULLIF(TRIM(@whitespace FROM customer_city COLLATE Latin1_General_BIN2), N''),
        customer_state
    FROM raw.olist_customers;
    PRINT CONCAT('stg.customers: ', @@ROWCOUNT, ' rows');

    TRUNCATE TABLE stg.geolocation;
    INSERT INTO stg.geolocation (geolocation_zip_code_prefix, geolocation_lat, geolocation_lng, geolocation_city, geolocation_state)
    SELECT
        geolocation_zip_code_prefix,
        TRY_CONVERT(FLOAT, geolocation_lat),
        TRY_CONVERT(FLOAT, geolocation_lng),
        NULLIF(TRIM(@whitespace FROM geolocation_city COLLATE Latin1_General_BIN2), N''),
        geolocation_state
    FROM raw.olist_geolocation;
    PRINT CONCAT('stg.geolocation: ', @@ROWCOUNT, ' rows');

    TRUNCATE TABLE stg.order_items;
    INSERT INTO stg.order_items (order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value)
    SELECT
        order_id,
        TRY_CONVERT(INT, order_item_id),
        product_id,
        seller_id,
        TRY_CONVERT(DATETIME2(0), shipping_limit_date, 120),
        TRY_CONVERT(DECIMAL(10, 2), price),
        TRY_CONVERT(DECIMAL(10, 2), freight_value)
    FROM raw.olist_order_items;
    PRINT CONCAT('stg.order_items: ', @@ROWCOUNT, ' rows');

    TRUNCATE TABLE stg.order_payments;
    INSERT INTO stg.order_payments (order_id, payment_sequential, payment_type, payment_installments, payment_value)
    SELECT
        order_id,
        TRY_CONVERT(INT, payment_sequential),
        payment_type,
        TRY_CONVERT(INT, payment_installments),
        TRY_CONVERT(DECIMAL(10, 2), payment_value)
    FROM raw.olist_order_payments;
    PRINT CONCAT('stg.order_payments: ', @@ROWCOUNT, ' rows');

    TRUNCATE TABLE stg.order_reviews;
    INSERT INTO stg.order_reviews (review_id, order_id, review_score, review_comment_title, review_comment_message,
                                   review_creation_date, review_answer_timestamp)
    SELECT
        review_id,
        order_id,
        TRY_CONVERT(INT, review_score),
        NULLIF(TRIM(@whitespace FROM review_comment_title COLLATE Latin1_General_BIN2), N''),
        NULLIF(TRIM(@whitespace FROM review_comment_message COLLATE Latin1_General_BIN2), N''),
        TRY_CONVERT(DATETIME2(0), review_creation_date, 120),
        TRY_CONVERT(DATETIME2(0), review_answer_timestamp, 120)
    FROM raw.olist_order_reviews;
    PRINT CONCAT('stg.order_reviews: ', @@ROWCOUNT, ' rows');

    TRUNCATE TABLE stg.orders;
    INSERT INTO stg.orders (order_id, customer_id, order_status, order_purchase_timestamp, order_approved_at,
                            order_delivered_carrier_date, order_delivered_customer_date, order_estimated_delivery_date)
    SELECT
        order_id,
        customer_id,
        order_status,
        TRY_CONVERT(DATETIME2(0), order_purchase_timestamp, 120),
        TRY_CONVERT(DATETIME2(0), order_approved_at, 120),
        TRY_CONVERT(DATETIME2(0), order_delivered_carrier_date, 120),
        TRY_CONVERT(DATETIME2(0), order_delivered_customer_date, 120),
        TRY_CONVERT(DATE, order_estimated_delivery_date, 120)
    FROM raw.olist_orders;
    PRINT CONCAT('stg.orders: ', @@ROWCOUNT, ' rows');

    TRUNCATE TABLE stg.products;
    INSERT INTO stg.products (product_id, product_category_name, product_name_length, product_description_length,
                              product_photos_qty, product_weight_g, product_length_cm, product_height_cm, product_width_cm)
    SELECT
        product_id,
        NULLIF(TRIM(@whitespace FROM product_category_name COLLATE Latin1_General_BIN2), N''),
        TRY_CONVERT(INT, product_name_lenght),
        TRY_CONVERT(INT, product_description_lenght),
        TRY_CONVERT(INT, product_photos_qty),
        TRY_CONVERT(INT, product_weight_g),
        TRY_CONVERT(INT, product_length_cm),
        TRY_CONVERT(INT, product_height_cm),
        TRY_CONVERT(INT, product_width_cm)
    FROM raw.olist_products;
    PRINT CONCAT('stg.products: ', @@ROWCOUNT, ' rows');

    TRUNCATE TABLE stg.sellers;
    INSERT INTO stg.sellers (seller_id, seller_zip_code_prefix, seller_city, seller_state)
    SELECT
        seller_id,
        seller_zip_code_prefix,
        NULLIF(TRIM(@whitespace FROM seller_city COLLATE Latin1_General_BIN2), N''),
        seller_state
    FROM raw.olist_sellers;
    PRINT CONCAT('stg.sellers: ', @@ROWCOUNT, ' rows');

    TRUNCATE TABLE stg.category_translation;
    INSERT INTO stg.category_translation (product_category_name, product_category_name_english)
    SELECT
        NULLIF(TRIM(@whitespace FROM product_category_name COLLATE Latin1_General_BIN2), N''),
        NULLIF(TRIM(@whitespace FROM product_category_name_english COLLATE Latin1_General_BIN2), N'')
    FROM raw.product_category_name_translation;
    PRINT CONCAT('stg.category_translation: ', @@ROWCOUNT, ' rows');

    COMMIT;
END;
GO
