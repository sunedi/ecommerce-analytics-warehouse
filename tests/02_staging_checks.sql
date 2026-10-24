/*
Checks that staging is a complete, faithful, typed copy of raw.

1. Row counts: every staging table has exactly as many rows as its raw table.
2. Values kept: no value was lost when converting text to numbers and dates.
   TRY_CONVERT returns NULL on failure, so a column that had N values in raw
   must still have N values in staging. Text columns may only lose values that
   were blank (nothing but spaces, tabs or line breaks).
3. Control totals: money columns add up to exactly the same amount.
4. Accepted values and formats: statuses, payment types, scores, states,
   IDs and ZIP prefixes all look the way the rest of the project assumes.

Returns one row per check, then raises an error if any check failed.
*/
USE EcommerceDW;
GO

SET NOCOUNT ON;

-- Matches text that contains at least one character other than space, tab, CR or LF
DECLARE @has_text NVARCHAR(10) = N'%[^' + NCHAR(32) + NCHAR(9) + NCHAR(13) + NCHAR(10) + N']%';

-- expected and actual keep 4 decimal places, so a rounding difference smaller than
-- one centavo (e.g. 10.005 stored as 10.01) still shows up as a mismatch
DROP TABLE IF EXISTS #checks;
CREATE TABLE #checks (
    check_group VARCHAR(20)    NOT NULL,
    check_name  NVARCHAR(200)  NOT NULL,
    expected    DECIMAL(19, 4) NOT NULL,
    actual      DECIMAL(19, 4) NOT NULL,
    result      AS CASE WHEN expected = actual THEN 'PASS' ELSE 'FAIL' END
);

-- 1. Row counts
INSERT INTO #checks (check_group, check_name, expected, actual)
SELECT 'row count', 'customers',            (SELECT COUNT_BIG(*) FROM raw.olist_customers),                   (SELECT COUNT_BIG(*) FROM stg.customers)
UNION ALL SELECT 'row count', 'geolocation',          (SELECT COUNT_BIG(*) FROM raw.olist_geolocation),                 (SELECT COUNT_BIG(*) FROM stg.geolocation)
UNION ALL SELECT 'row count', 'order_items',          (SELECT COUNT_BIG(*) FROM raw.olist_order_items),                 (SELECT COUNT_BIG(*) FROM stg.order_items)
UNION ALL SELECT 'row count', 'order_payments',       (SELECT COUNT_BIG(*) FROM raw.olist_order_payments),              (SELECT COUNT_BIG(*) FROM stg.order_payments)
UNION ALL SELECT 'row count', 'order_reviews',        (SELECT COUNT_BIG(*) FROM raw.olist_order_reviews),               (SELECT COUNT_BIG(*) FROM stg.order_reviews)
UNION ALL SELECT 'row count', 'orders',               (SELECT COUNT_BIG(*) FROM raw.olist_orders),                      (SELECT COUNT_BIG(*) FROM stg.orders)
UNION ALL SELECT 'row count', 'products',             (SELECT COUNT_BIG(*) FROM raw.olist_products),                    (SELECT COUNT_BIG(*) FROM stg.products)
UNION ALL SELECT 'row count', 'sellers',              (SELECT COUNT_BIG(*) FROM raw.olist_sellers),                     (SELECT COUNT_BIG(*) FROM stg.sellers)
UNION ALL SELECT 'row count', 'category_translation', (SELECT COUNT_BIG(*) FROM raw.product_category_name_translation), (SELECT COUNT_BIG(*) FROM stg.category_translation);

-- 2a. Values kept in converted columns: COUNT(column) counts non-NULL values
INSERT INTO #checks (check_group, check_name, expected, actual)
SELECT 'values kept', 'geolocation.geolocation_lat',             (SELECT COUNT(geolocation_lat) FROM raw.olist_geolocation),               (SELECT COUNT(geolocation_lat) FROM stg.geolocation)
UNION ALL SELECT 'values kept', 'geolocation.geolocation_lng',             (SELECT COUNT(geolocation_lng) FROM raw.olist_geolocation),               (SELECT COUNT(geolocation_lng) FROM stg.geolocation)
UNION ALL SELECT 'values kept', 'order_items.order_item_id',               (SELECT COUNT(order_item_id) FROM raw.olist_order_items),                 (SELECT COUNT(order_item_id) FROM stg.order_items)
UNION ALL SELECT 'values kept', 'order_items.shipping_limit_date',         (SELECT COUNT(shipping_limit_date) FROM raw.olist_order_items),           (SELECT COUNT(shipping_limit_date) FROM stg.order_items)
UNION ALL SELECT 'values kept', 'order_items.price',                       (SELECT COUNT(price) FROM raw.olist_order_items),                         (SELECT COUNT(price) FROM stg.order_items)
UNION ALL SELECT 'values kept', 'order_items.freight_value',               (SELECT COUNT(freight_value) FROM raw.olist_order_items),                 (SELECT COUNT(freight_value) FROM stg.order_items)
UNION ALL SELECT 'values kept', 'order_payments.payment_sequential',       (SELECT COUNT(payment_sequential) FROM raw.olist_order_payments),         (SELECT COUNT(payment_sequential) FROM stg.order_payments)
UNION ALL SELECT 'values kept', 'order_payments.payment_installments',     (SELECT COUNT(payment_installments) FROM raw.olist_order_payments),       (SELECT COUNT(payment_installments) FROM stg.order_payments)
UNION ALL SELECT 'values kept', 'order_payments.payment_value',            (SELECT COUNT(payment_value) FROM raw.olist_order_payments),              (SELECT COUNT(payment_value) FROM stg.order_payments)
UNION ALL SELECT 'values kept', 'order_reviews.review_score',              (SELECT COUNT(review_score) FROM raw.olist_order_reviews),                (SELECT COUNT(review_score) FROM stg.order_reviews)
UNION ALL SELECT 'values kept', 'order_reviews.review_creation_date',      (SELECT COUNT(review_creation_date) FROM raw.olist_order_reviews),        (SELECT COUNT(review_creation_date) FROM stg.order_reviews)
UNION ALL SELECT 'values kept', 'order_reviews.review_answer_timestamp',   (SELECT COUNT(review_answer_timestamp) FROM raw.olist_order_reviews),     (SELECT COUNT(review_answer_timestamp) FROM stg.order_reviews)
UNION ALL SELECT 'values kept', 'orders.order_purchase_timestamp',         (SELECT COUNT(order_purchase_timestamp) FROM raw.olist_orders),           (SELECT COUNT(order_purchase_timestamp) FROM stg.orders)
UNION ALL SELECT 'values kept', 'orders.order_approved_at',                (SELECT COUNT(order_approved_at) FROM raw.olist_orders),                  (SELECT COUNT(order_approved_at) FROM stg.orders)
UNION ALL SELECT 'values kept', 'orders.order_delivered_carrier_date',     (SELECT COUNT(order_delivered_carrier_date) FROM raw.olist_orders),       (SELECT COUNT(order_delivered_carrier_date) FROM stg.orders)
UNION ALL SELECT 'values kept', 'orders.order_delivered_customer_date',    (SELECT COUNT(order_delivered_customer_date) FROM raw.olist_orders),      (SELECT COUNT(order_delivered_customer_date) FROM stg.orders)
UNION ALL SELECT 'values kept', 'orders.order_estimated_delivery_date',    (SELECT COUNT(order_estimated_delivery_date) FROM raw.olist_orders),      (SELECT COUNT(order_estimated_delivery_date) FROM stg.orders)
UNION ALL SELECT 'values kept', 'products.product_name_length',            (SELECT COUNT(product_name_lenght) FROM raw.olist_products),              (SELECT COUNT(product_name_length) FROM stg.products)
UNION ALL SELECT 'values kept', 'products.product_description_length',     (SELECT COUNT(product_description_lenght) FROM raw.olist_products),       (SELECT COUNT(product_description_length) FROM stg.products)
UNION ALL SELECT 'values kept', 'products.product_photos_qty',             (SELECT COUNT(product_photos_qty) FROM raw.olist_products),               (SELECT COUNT(product_photos_qty) FROM stg.products)
UNION ALL SELECT 'values kept', 'products.product_weight_g',               (SELECT COUNT(product_weight_g) FROM raw.olist_products),                 (SELECT COUNT(product_weight_g) FROM stg.products)
UNION ALL SELECT 'values kept', 'products.product_length_cm',              (SELECT COUNT(product_length_cm) FROM raw.olist_products),                (SELECT COUNT(product_length_cm) FROM stg.products)
UNION ALL SELECT 'values kept', 'products.product_height_cm',              (SELECT COUNT(product_height_cm) FROM raw.olist_products),                (SELECT COUNT(product_height_cm) FROM stg.products)
UNION ALL SELECT 'values kept', 'products.product_width_cm',               (SELECT COUNT(product_width_cm) FROM raw.olist_products),                 (SELECT COUNT(product_width_cm) FROM stg.products);

-- 2b. Values kept in trimmed text columns: only blank values may become NULL.
-- The binary collation makes LIKE compare exact characters, so emoji count as text.
INSERT INTO #checks (check_group, check_name, expected, actual)
SELECT 'values kept', 'customers.customer_city',                       (SELECT COUNT(*) FROM raw.olist_customers WHERE customer_city COLLATE Latin1_General_BIN2 LIKE @has_text),                                     (SELECT COUNT(customer_city) FROM stg.customers)
UNION ALL SELECT 'values kept', 'geolocation.geolocation_city',                   (SELECT COUNT(*) FROM raw.olist_geolocation WHERE geolocation_city COLLATE Latin1_General_BIN2 LIKE @has_text),                              (SELECT COUNT(geolocation_city) FROM stg.geolocation)
UNION ALL SELECT 'values kept', 'order_reviews.review_comment_title',             (SELECT COUNT(*) FROM raw.olist_order_reviews WHERE review_comment_title COLLATE Latin1_General_BIN2 LIKE @has_text),                        (SELECT COUNT(review_comment_title) FROM stg.order_reviews)
UNION ALL SELECT 'values kept', 'order_reviews.review_comment_message',           (SELECT COUNT(*) FROM raw.olist_order_reviews WHERE review_comment_message COLLATE Latin1_General_BIN2 LIKE @has_text),                      (SELECT COUNT(review_comment_message) FROM stg.order_reviews)
UNION ALL SELECT 'values kept', 'products.product_category_name',                 (SELECT COUNT(*) FROM raw.olist_products WHERE product_category_name COLLATE Latin1_General_BIN2 LIKE @has_text),                            (SELECT COUNT(product_category_name) FROM stg.products)
UNION ALL SELECT 'values kept', 'sellers.seller_city',                            (SELECT COUNT(*) FROM raw.olist_sellers WHERE seller_city COLLATE Latin1_General_BIN2 LIKE @has_text),                                       (SELECT COUNT(seller_city) FROM stg.sellers)
UNION ALL SELECT 'values kept', 'category_translation.product_category_name',     (SELECT COUNT(*) FROM raw.product_category_name_translation WHERE product_category_name COLLATE Latin1_General_BIN2 LIKE @has_text),         (SELECT COUNT(product_category_name) FROM stg.category_translation)
UNION ALL SELECT 'values kept', 'category_translation.product_category_name_english', (SELECT COUNT(*) FROM raw.product_category_name_translation WHERE product_category_name_english COLLATE Latin1_General_BIN2 LIKE @has_text), (SELECT COUNT(product_category_name_english) FROM stg.category_translation);

-- 3. Control totals: converting to DECIMAL(10,2) must not round any amount
INSERT INTO #checks (check_group, check_name, expected, actual)
SELECT 'control total', 'sum of order_items.price',            (SELECT SUM(TRY_CONVERT(DECIMAL(18, 4), price)) FROM raw.olist_order_items),            (SELECT SUM(price) FROM stg.order_items)
UNION ALL SELECT 'control total', 'sum of order_items.freight_value',    (SELECT SUM(TRY_CONVERT(DECIMAL(18, 4), freight_value)) FROM raw.olist_order_items),    (SELECT SUM(freight_value) FROM stg.order_items)
UNION ALL SELECT 'control total', 'sum of order_payments.payment_value', (SELECT SUM(TRY_CONVERT(DECIMAL(18, 4), payment_value)) FROM raw.olist_order_payments), (SELECT SUM(payment_value) FROM stg.order_payments);

-- 4. Accepted values and formats: expected is 0 rows breaking the rule
DROP TABLE IF EXISTS #brazil_states;
SELECT state INTO #brazil_states
FROM (VALUES ('AC'), ('AL'), ('AM'), ('AP'), ('BA'), ('CE'), ('DF'), ('ES'), ('GO'), ('MA'), ('MG'), ('MS'), ('MT'), ('PA'),
             ('PB'), ('PE'), ('PI'), ('PR'), ('RJ'), ('RN'), ('RO'), ('RR'), ('RS'), ('SC'), ('SE'), ('SP'), ('TO')) AS s(state);

-- 32 lowercase hexadecimal characters. The pattern is 256 characters long (8 x 32), so the
-- variable must be at least that wide or SQL Server silently cuts the pattern short.
DECLARE @id_pattern VARCHAR(256) = REPLICATE('[0-9a-f]', 32);

INSERT INTO #checks (check_group, check_name, expected, actual)
SELECT 'accepted values', 'orders.order_status is a known status', 0,
    (SELECT COUNT(*) FROM stg.orders
     WHERE order_status IS NULL
        OR order_status NOT IN ('created', 'approved', 'invoiced', 'processing', 'shipped', 'delivered', 'canceled', 'unavailable'))
UNION ALL SELECT 'accepted values', 'order_payments.payment_type is a known type', 0,
    (SELECT COUNT(*) FROM stg.order_payments
     WHERE payment_type IS NULL
        OR payment_type NOT IN ('credit_card', 'boleto', 'voucher', 'debit_card', 'not_defined'))
UNION ALL SELECT 'accepted values', 'order_reviews.review_score is 1 to 5', 0,
    (SELECT COUNT(*) FROM stg.order_reviews WHERE review_score IS NULL OR review_score NOT BETWEEN 1 AND 5)
UNION ALL SELECT 'accepted values', 'customers.customer_state is a Brazilian state', 0,
    (SELECT COUNT(*) FROM stg.customers WHERE customer_state IS NULL OR customer_state NOT IN (SELECT state FROM #brazil_states))
UNION ALL SELECT 'accepted values', 'sellers.seller_state is a Brazilian state', 0,
    (SELECT COUNT(*) FROM stg.sellers WHERE seller_state IS NULL OR seller_state NOT IN (SELECT state FROM #brazil_states))
UNION ALL SELECT 'accepted values', 'geolocation.geolocation_state is a Brazilian state', 0,
    (SELECT COUNT(*) FROM stg.geolocation WHERE geolocation_state IS NULL OR geolocation_state NOT IN (SELECT state FROM #brazil_states))
UNION ALL SELECT 'format', 'every ID is 32 lowercase hex characters', 0,
    (SELECT COUNT(*) FROM (
        SELECT customer_id AS id FROM stg.customers
        UNION ALL SELECT customer_unique_id FROM stg.customers
        UNION ALL SELECT order_id FROM stg.orders
        UNION ALL SELECT customer_id FROM stg.orders
        UNION ALL SELECT order_id FROM stg.order_items
        UNION ALL SELECT product_id FROM stg.order_items
        UNION ALL SELECT seller_id FROM stg.order_items
        UNION ALL SELECT order_id FROM stg.order_payments
        UNION ALL SELECT review_id FROM stg.order_reviews
        UNION ALL SELECT order_id FROM stg.order_reviews
        UNION ALL SELECT product_id FROM stg.products
        UNION ALL SELECT seller_id FROM stg.sellers
     ) AS ids
     WHERE id IS NULL OR id COLLATE Latin1_General_BIN2 NOT LIKE @id_pattern)
UNION ALL SELECT 'format', 'every ZIP code prefix is 5 digits', 0,
    (SELECT COUNT(*) FROM (
        SELECT customer_zip_code_prefix AS zip FROM stg.customers
        UNION ALL SELECT seller_zip_code_prefix FROM stg.sellers
        UNION ALL SELECT geolocation_zip_code_prefix FROM stg.geolocation
     ) AS zips
     WHERE zip IS NULL OR zip NOT LIKE '[0-9][0-9][0-9][0-9][0-9]');

SELECT check_group, check_name, expected, actual, result
FROM #checks
ORDER BY CASE result WHEN 'FAIL' THEN 0 ELSE 1 END, check_group, check_name;

IF EXISTS (SELECT 1 FROM #checks WHERE result = 'FAIL')
    THROW 50002, 'Staging checks failed. See the results above.', 1;

DECLARE @check_count INT = (SELECT COUNT(*) FROM #checks);
PRINT CONCAT('All ', @check_count, ' staging checks passed.');
GO
