/*
Staging tables: one per raw table, with proper data types and corrected names.

Rules for this layer:
- One row in, one row out. Staging never filters, deduplicates or joins, so
  every raw row can be traced to exactly one staging row. Duplicates and
  orphaned keys are measured here and resolved in the warehouse layer.
- IDs are always 32 hexadecimal characters, so they are stored as CHAR(32).
  ZIP code prefixes stay as text (CHAR(5)) to keep leading zeros.
- Money is DECIMAL(10,2): every source value has at most two decimal places.
- Latitude and longitude are FLOAT: they are measurements, not money, and the
  source has more decimal places than DECIMAL would need to keep.
- order_estimated_delivery_date is always midnight in the source, so it is a DATE.
  Every other timestamp keeps its time of day as DATETIME2(0) (whole seconds).
- Columns are nullable: data problems are reported by the profiling queries and
  tests instead of stopping the load.
*/
USE EcommerceDW;
GO

DROP TABLE IF EXISTS stg.customers;
CREATE TABLE stg.customers (
    customer_id              CHAR(32),
    customer_unique_id       CHAR(32),
    customer_zip_code_prefix CHAR(5),
    customer_city            NVARCHAR(100),
    customer_state           CHAR(2)
);

DROP TABLE IF EXISTS stg.geolocation;
CREATE TABLE stg.geolocation (
    geolocation_zip_code_prefix CHAR(5),
    geolocation_lat             FLOAT,
    geolocation_lng             FLOAT,
    geolocation_city            NVARCHAR(100),
    geolocation_state           CHAR(2)
);

DROP TABLE IF EXISTS stg.order_items;
CREATE TABLE stg.order_items (
    order_id            CHAR(32),
    order_item_id       INT,          -- position of the item within its order: 1, 2, 3...
    product_id          CHAR(32),
    seller_id           CHAR(32),
    shipping_limit_date DATETIME2(0),
    price               DECIMAL(10, 2),
    freight_value       DECIMAL(10, 2)
);

DROP TABLE IF EXISTS stg.order_payments;
CREATE TABLE stg.order_payments (
    order_id             CHAR(32),
    payment_sequential   INT,
    payment_type         VARCHAR(20),
    payment_installments INT,
    payment_value        DECIMAL(10, 2)
);

DROP TABLE IF EXISTS stg.order_reviews;
CREATE TABLE stg.order_reviews (
    review_id               CHAR(32),
    order_id                CHAR(32),
    review_score            INT,
    review_comment_title    NVARCHAR(200),
    review_comment_message  NVARCHAR(1000),
    review_creation_date    DATETIME2(0),  -- usually midnight, but 85 rows have a time
    review_answer_timestamp DATETIME2(0)
);

DROP TABLE IF EXISTS stg.orders;
CREATE TABLE stg.orders (
    order_id                      CHAR(32),
    customer_id                   CHAR(32),
    order_status                  VARCHAR(20),
    order_purchase_timestamp      DATETIME2(0),
    order_approved_at             DATETIME2(0),
    order_delivered_carrier_date  DATETIME2(0),
    order_delivered_customer_date DATETIME2(0),
    order_estimated_delivery_date DATE
);

DROP TABLE IF EXISTS stg.products;
CREATE TABLE stg.products (
    product_id                 CHAR(32),
    product_category_name      NVARCHAR(100),
    product_name_length        INT,  -- spelt 'lenght' in the source
    product_description_length INT,  -- spelt 'lenght' in the source
    product_photos_qty         INT,
    product_weight_g           INT,
    product_length_cm          INT,
    product_height_cm          INT,
    product_width_cm           INT
);

DROP TABLE IF EXISTS stg.sellers;
CREATE TABLE stg.sellers (
    seller_id              CHAR(32),
    seller_zip_code_prefix CHAR(5),
    seller_city            NVARCHAR(100),
    seller_state           CHAR(2)
);

DROP TABLE IF EXISTS stg.category_translation;
CREATE TABLE stg.category_translation (
    product_category_name         NVARCHAR(100),
    product_category_name_english NVARCHAR(100)
);
GO
