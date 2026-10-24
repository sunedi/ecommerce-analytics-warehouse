/*
Raw tables: one per Olist CSV file, loaded without any changes.

- Every column is NVARCHAR, so a badly formatted value can never stop the load.
  Converting to dates and numbers happens in the staging layer, where values
  that fail to convert can be counted and investigated.
- Keeping ZIP code prefixes as text also preserves leading zeros (e.g. '01037').
- Column names match the CSV headers exactly, including the source's spelling
  'lenght' in olist_products. Names are corrected in staging.
- Widths leave headroom above the longest value found in each column, so a
  much longer value in a future file fails the load loudly instead of being cut short.

The tables are dropped and recreated on every build; the data is reloaded by raw.usp_load_raw.
*/
USE EcommerceDW;
GO

DROP TABLE IF EXISTS raw.olist_customers;
CREATE TABLE raw.olist_customers (
    customer_id              NVARCHAR(50),
    customer_unique_id       NVARCHAR(50),
    customer_zip_code_prefix NVARCHAR(10),
    customer_city            NVARCHAR(100),
    customer_state           NVARCHAR(10)
);

DROP TABLE IF EXISTS raw.olist_geolocation;
CREATE TABLE raw.olist_geolocation (
    geolocation_zip_code_prefix NVARCHAR(10),
    geolocation_lat             NVARCHAR(50),
    geolocation_lng             NVARCHAR(50),
    geolocation_city            NVARCHAR(100),
    geolocation_state           NVARCHAR(10)
);

DROP TABLE IF EXISTS raw.olist_order_items;
CREATE TABLE raw.olist_order_items (
    order_id            NVARCHAR(50),
    order_item_id       NVARCHAR(10),
    product_id          NVARCHAR(50),
    seller_id           NVARCHAR(50),
    shipping_limit_date NVARCHAR(30),
    price               NVARCHAR(20),
    freight_value       NVARCHAR(20)
);

DROP TABLE IF EXISTS raw.olist_order_payments;
CREATE TABLE raw.olist_order_payments (
    order_id             NVARCHAR(50),
    payment_sequential   NVARCHAR(10),
    payment_type         NVARCHAR(50),
    payment_installments NVARCHAR(10),
    payment_value        NVARCHAR(20)
);

DROP TABLE IF EXISTS raw.olist_order_reviews;
CREATE TABLE raw.olist_order_reviews (
    review_id               NVARCHAR(50),
    order_id                NVARCHAR(50),
    review_score            NVARCHAR(10),
    review_comment_title    NVARCHAR(200),
    review_comment_message  NVARCHAR(1000),
    review_creation_date    NVARCHAR(30),
    review_answer_timestamp NVARCHAR(30)
);

DROP TABLE IF EXISTS raw.olist_orders;
CREATE TABLE raw.olist_orders (
    order_id                      NVARCHAR(50),
    customer_id                   NVARCHAR(50),
    order_status                  NVARCHAR(50),
    order_purchase_timestamp      NVARCHAR(30),
    order_approved_at             NVARCHAR(30),
    order_delivered_carrier_date  NVARCHAR(30),
    order_delivered_customer_date NVARCHAR(30),
    order_estimated_delivery_date NVARCHAR(30)
);

DROP TABLE IF EXISTS raw.olist_products;
CREATE TABLE raw.olist_products (
    product_id                 NVARCHAR(50),
    product_category_name      NVARCHAR(100),
    product_name_lenght        NVARCHAR(10),
    product_description_lenght NVARCHAR(10),
    product_photos_qty         NVARCHAR(10),
    product_weight_g           NVARCHAR(10),
    product_length_cm          NVARCHAR(10),
    product_height_cm          NVARCHAR(10),
    product_width_cm           NVARCHAR(10)
);

DROP TABLE IF EXISTS raw.olist_sellers;
CREATE TABLE raw.olist_sellers (
    seller_id              NVARCHAR(50),
    seller_zip_code_prefix NVARCHAR(10),
    seller_city            NVARCHAR(100),
    seller_state           NVARCHAR(10)
);

DROP TABLE IF EXISTS raw.product_category_name_translation;
CREATE TABLE raw.product_category_name_translation (
    product_category_name         NVARCHAR(100),
    product_category_name_english NVARCHAR(100)
);
GO
