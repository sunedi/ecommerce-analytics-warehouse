/*
Star schema: dimensions and facts in the dw schema.

Grain (what one row means):
    dim_date        one calendar day
    dim_customer    one customer (customer_unique_id) at one location, with the dates
                    that location applied (slowly changing dimension, Type 2)
    dim_product     one product
    dim_seller      one seller
    fct_order       one order, with its items, payments and reviews summed to order level
    fct_order_item  one item in an order
    fct_payment     one payment towards an order
    fct_review      one review of one order (a review can cover several orders)

Dimensions use surrogate keys (customer_key, product_key, seller_key): plain integers
that the warehouse assigns, separate from the source IDs. dim_customer needs one,
because a customer has a row per location. The others follow the same pattern.

Primary keys enforce each table's grain, and foreign keys guarantee every fact row
points to a real dimension row. Facts are dropped first because they reference
the dimensions.
*/
USE EcommerceDW;
GO

DROP TABLE IF EXISTS dw.fct_review;
DROP TABLE IF EXISTS dw.fct_payment;
DROP TABLE IF EXISTS dw.fct_order_item;
DROP TABLE IF EXISTS dw.fct_order;
DROP TABLE IF EXISTS dw.dim_customer;
DROP TABLE IF EXISTS dw.dim_product;
DROP TABLE IF EXISTS dw.dim_seller;
DROP TABLE IF EXISTS dw.dim_date;
GO

-- Dimensions

CREATE TABLE dw.dim_date (
    date_key           INT         NOT NULL,  -- yyyymmdd, e.g. 20170315
    full_date          DATE        NOT NULL,
    [year]             INT         NOT NULL,
    [quarter]          INT         NOT NULL,
    [month]            INT         NOT NULL,
    month_name         VARCHAR(9)  NOT NULL,
    year_month         CHAR(7)     NOT NULL,  -- e.g. 2017-03, sorts correctly as text
    month_start        DATE        NOT NULL,
    day_of_month       INT         NOT NULL,
    day_of_week        INT         NOT NULL,  -- 1 = Monday ... 7 = Sunday
    day_name           VARCHAR(9)  NOT NULL,
    is_weekend         BIT         NOT NULL,
    in_analysis_window BIT         NOT NULL,  -- Jan 2017 to Aug 2018, the complete months (assumptions.md, decision 3)
    CONSTRAINT pk_dim_date PRIMARY KEY (date_key),
    CONSTRAINT uq_dim_date_full_date UNIQUE (full_date)
);

CREATE TABLE dw.dim_customer (
    customer_key       INT           NOT NULL,
    customer_unique_id CHAR(32)      NOT NULL,
    version_number     INT           NOT NULL,  -- 1 for the first location, 2 after the first move...
    zip_code_prefix    CHAR(5)       NOT NULL,
    city               NVARCHAR(100) NOT NULL,
    [state]            CHAR(2)       NOT NULL,
    latitude           FLOAT         NULL,      -- NULL when the ZIP prefix has no location
    longitude          FLOAT         NULL,
    valid_from         DATETIME2(0)  NOT NULL,  -- first purchase from this location
    valid_to           DATETIME2(0)  NOT NULL,  -- next version's valid_from; 9999-12-31 for the current version
    is_current         BIT           NOT NULL,
    CONSTRAINT pk_dim_customer PRIMARY KEY (customer_key),
    CONSTRAINT uq_dim_customer_version UNIQUE (customer_unique_id, version_number)
);

CREATE TABLE dw.dim_product (
    product_key              INT           NOT NULL,
    product_id               CHAR(32)      NOT NULL,
    category_name            NVARCHAR(100) NOT NULL,  -- English; 'unknown' when the source has no category
    category_name_portuguese NVARCHAR(100) NULL,
    name_length              INT           NULL,
    description_length       INT           NULL,
    photos_qty               INT           NULL,
    weight_g                 INT           NULL,
    length_cm                INT           NULL,
    height_cm                INT           NULL,
    width_cm                 INT           NULL,
    CONSTRAINT pk_dim_product PRIMARY KEY (product_key),
    CONSTRAINT uq_dim_product_id UNIQUE (product_id)
);

CREATE TABLE dw.dim_seller (
    seller_key      INT           NOT NULL,
    seller_id       CHAR(32)      NOT NULL,
    zip_code_prefix CHAR(5)       NOT NULL,
    city            NVARCHAR(100) NOT NULL,
    [state]         CHAR(2)       NOT NULL,
    latitude        FLOAT         NULL,
    longitude       FLOAT         NULL,
    CONSTRAINT pk_dim_seller PRIMARY KEY (seller_key),
    CONSTRAINT uq_dim_seller_id UNIQUE (seller_id)
);

-- Facts

CREATE TABLE dw.fct_order (
    order_id                    CHAR(32)       NOT NULL,
    customer_key                INT            NOT NULL,
    purchase_date_key           INT            NOT NULL,
    delivered_date_key          INT            NULL,
    estimated_delivery_date_key INT            NOT NULL,
    order_status                VARCHAR(20)    NOT NULL,
    is_revenue                  BIT            NOT NULL,  -- 1 for delivered orders (assumptions.md, decision 2)
    purchase_timestamp          DATETIME2(0)   NOT NULL,
    approved_at                 DATETIME2(0)   NULL,
    delivered_to_carrier_at     DATETIME2(0)   NULL,
    delivered_to_customer_at    DATETIME2(0)   NULL,
    estimated_delivery_date     DATE           NOT NULL,
    item_count                  INT            NOT NULL,  -- 0 for orders without items
    seller_count                INT            NOT NULL,
    item_total                  DECIMAL(12, 2) NOT NULL,  -- sum of item prices
    freight_total               DECIMAL(12, 2) NOT NULL,
    payment_count               INT            NOT NULL,
    payment_total               DECIMAL(12, 2) NOT NULL,
    delivery_days               DECIMAL(6, 2)  NULL,      -- purchase to delivered to customer, in days
    days_late                   INT            NULL,      -- delivered date minus estimated date; negative = early
    is_late                     BIT            NULL,
    review_count                INT            NOT NULL,
    review_score                INT            NULL,      -- most recently answered review (decision 6)
    CONSTRAINT pk_fct_order PRIMARY KEY (order_id),
    CONSTRAINT fk_fct_order_customer       FOREIGN KEY (customer_key)                REFERENCES dw.dim_customer (customer_key),
    CONSTRAINT fk_fct_order_purchase_date  FOREIGN KEY (purchase_date_key)           REFERENCES dw.dim_date (date_key),
    CONSTRAINT fk_fct_order_delivered_date FOREIGN KEY (delivered_date_key)          REFERENCES dw.dim_date (date_key),
    CONSTRAINT fk_fct_order_estimated_date FOREIGN KEY (estimated_delivery_date_key) REFERENCES dw.dim_date (date_key)
);

CREATE TABLE dw.fct_order_item (
    order_id          CHAR(32)       NOT NULL,
    order_item_id     INT            NOT NULL,
    product_key       INT            NOT NULL,
    seller_key        INT            NOT NULL,
    customer_key      INT            NOT NULL,
    purchase_date_key INT            NOT NULL,
    order_status      VARCHAR(20)    NOT NULL,
    is_revenue        BIT            NOT NULL,
    shipping_limit_at DATETIME2(0)   NOT NULL,
    price             DECIMAL(10, 2) NOT NULL,
    freight_value     DECIMAL(10, 2) NOT NULL,
    CONSTRAINT pk_fct_order_item PRIMARY KEY (order_id, order_item_id),
    CONSTRAINT fk_fct_order_item_order         FOREIGN KEY (order_id)          REFERENCES dw.fct_order (order_id),
    CONSTRAINT fk_fct_order_item_product       FOREIGN KEY (product_key)       REFERENCES dw.dim_product (product_key),
    CONSTRAINT fk_fct_order_item_seller        FOREIGN KEY (seller_key)        REFERENCES dw.dim_seller (seller_key),
    CONSTRAINT fk_fct_order_item_customer      FOREIGN KEY (customer_key)      REFERENCES dw.dim_customer (customer_key),
    CONSTRAINT fk_fct_order_item_purchase_date FOREIGN KEY (purchase_date_key) REFERENCES dw.dim_date (date_key)
);

CREATE TABLE dw.fct_payment (
    order_id             CHAR(32)       NOT NULL,
    payment_sequential   INT            NOT NULL,
    customer_key         INT            NOT NULL,
    purchase_date_key    INT            NOT NULL,
    payment_type         VARCHAR(20)    NOT NULL,
    payment_installments INT            NOT NULL,
    payment_value        DECIMAL(10, 2) NOT NULL,
    CONSTRAINT pk_fct_payment PRIMARY KEY (order_id, payment_sequential),
    CONSTRAINT fk_fct_payment_order         FOREIGN KEY (order_id)          REFERENCES dw.fct_order (order_id),
    CONSTRAINT fk_fct_payment_customer      FOREIGN KEY (customer_key)      REFERENCES dw.dim_customer (customer_key),
    CONSTRAINT fk_fct_payment_purchase_date FOREIGN KEY (purchase_date_key) REFERENCES dw.dim_date (date_key)
);

CREATE TABLE dw.fct_review (
    review_id           CHAR(32)       NOT NULL,
    order_id            CHAR(32)       NOT NULL,
    customer_key        INT            NOT NULL,
    created_date_key    INT            NOT NULL,
    review_score        INT            NOT NULL,
    has_comment         BIT            NOT NULL,  -- a title or a message was written
    comment_title       NVARCHAR(200)  NULL,
    comment_message     NVARCHAR(1000) NULL,
    created_at          DATETIME2(0)   NOT NULL,
    answered_at         DATETIME2(0)   NOT NULL,
    is_latest_for_order BIT            NOT NULL,  -- the review whose score fct_order uses
    CONSTRAINT pk_fct_review PRIMARY KEY (review_id, order_id),
    CONSTRAINT fk_fct_review_order        FOREIGN KEY (order_id)         REFERENCES dw.fct_order (order_id),
    CONSTRAINT fk_fct_review_customer     FOREIGN KEY (customer_key)     REFERENCES dw.dim_customer (customer_key),
    CONSTRAINT fk_fct_review_created_date FOREIGN KEY (created_date_key) REFERENCES dw.dim_date (date_key)
);
GO
