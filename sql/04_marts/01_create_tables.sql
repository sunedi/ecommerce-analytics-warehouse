/*
Marts: summary tables in the mart schema, shaped for a dashboard.

Every mart stores SUMS and COUNTS (revenue, orders, review_score_sum, reviewed_orders...),
so any average or percentage can be recalculated correctly at any level:
    average review score = SUM(review_score_sum) / SUM(reviewed_orders)
Averaging pre-calculated averages across rows gives the wrong answer, because each row
would count equally however many orders it holds.

Ratio columns (avg_..., ..._pct) appear only in marts whose rows are what you would
display one by one: one month, one seller, one customer, one delivery bucket.
Never average them across rows.

Revenue follows decision 2 (delivered orders only) throughout. Marts with a month
column carry in_analysis_window (decision 3) so a dashboard can filter on it.
*/
USE EcommerceDW;
GO

DROP TABLE IF EXISTS mart.monthly_performance;
CREATE TABLE mart.monthly_performance (
    month_start         DATE           NOT NULL,
    year_month          CHAR(7)        NOT NULL,
    in_analysis_window  BIT            NOT NULL,
    orders              INT            NOT NULL,  -- every order placed, any status
    delivered_orders    INT            NOT NULL,
    revenue             DECIMAL(14, 2) NOT NULL,
    freight             DECIMAL(14, 2) NOT NULL,
    customers           INT            NOT NULL,  -- distinct customers; NOT additive across months
    new_customers       INT            NOT NULL,  -- first delivered order in this month; additive
    delivered_with_date INT            NOT NULL,
    late_orders         INT            NOT NULL,
    delivery_days_sum   DECIMAL(14, 2) NOT NULL,
    reviewed_orders     INT            NOT NULL,
    review_score_sum    INT            NOT NULL,
    one_star_orders     INT            NOT NULL,
    -- Ratios for showing one month at a time
    avg_order_value     DECIMAL(10, 2) NULL,
    freight_pct         DECIMAL(5, 1)  NULL,
    late_pct            DECIMAL(5, 1)  NULL,
    avg_delivery_days   DECIMAL(5, 1)  NULL,
    avg_review_score    DECIMAL(3, 2)  NULL,
    CONSTRAINT pk_monthly_performance PRIMARY KEY (month_start)
);

DROP TABLE IF EXISTS mart.state_monthly;
CREATE TABLE mart.state_monthly (
    month_start         DATE           NOT NULL,
    [state]             CHAR(2)        NOT NULL,  -- customer's state when ordering (decision 5)
    state_name          VARCHAR(30)    NOT NULL,  -- without accents, e.g. Sao Paulo
    region              VARCHAR(15)    NOT NULL,  -- North, Northeast, Central-West, Southeast, South
    in_analysis_window  BIT            NOT NULL,
    delivered_orders    INT            NOT NULL,
    revenue             DECIMAL(14, 2) NOT NULL,
    freight             DECIMAL(14, 2) NOT NULL,
    delivered_with_date INT            NOT NULL,
    late_orders         INT            NOT NULL,
    delivery_days_sum   DECIMAL(14, 2) NOT NULL,
    reviewed_orders     INT            NOT NULL,
    review_score_sum    INT            NOT NULL,
    CONSTRAINT pk_state_monthly PRIMARY KEY (month_start, [state])
);

DROP TABLE IF EXISTS mart.category_monthly;
CREATE TABLE mart.category_monthly (
    month_start              DATE           NOT NULL,
    category_name            NVARCHAR(100)  NOT NULL,
    in_analysis_window       BIT            NOT NULL,
    orders                   INT            NOT NULL,  -- orders containing the category; NOT additive across categories
    items                    INT            NOT NULL,
    revenue                  DECIMAL(14, 2) NOT NULL,
    delivered_with_date      INT            NOT NULL,
    late_orders              INT            NOT NULL,
    reviewed_orders          INT            NOT NULL,
    review_score_sum         INT            NOT NULL,
    one_star_orders          INT            NOT NULL,
    on_time_reviewed_orders  INT            NOT NULL,
    on_time_review_score_sum INT            NOT NULL,
    CONSTRAINT pk_category_monthly PRIMARY KEY (month_start, category_name)
);

DROP TABLE IF EXISTS mart.seller_performance;
CREATE TABLE mart.seller_performance (
    seller_id            CHAR(32)       NOT NULL,
    [state]              CHAR(2)        NOT NULL,
    region               VARCHAR(15)    NOT NULL,
    latitude             FLOAT          NULL,
    longitude            FLOAT          NULL,
    first_sale_date      DATE           NULL,
    last_sale_date       DATE           NULL,
    delivered_orders     INT            NOT NULL,  -- NOT additive across sellers (multi-seller orders)
    items_sold           INT            NOT NULL,
    revenue              DECIMAL(14, 2) NOT NULL,
    freight              DECIMAL(14, 2) NOT NULL,
    -- Delivery and reviews use single-seller orders only: in a multi-seller order there is
    -- no way to tell whose parcel was late or what the review was about
    single_seller_orders INT            NOT NULL,
    late_orders          INT            NOT NULL,
    delivery_days_sum    DECIMAL(14, 2) NOT NULL,
    reviewed_orders      INT            NOT NULL,
    review_score_sum     INT            NOT NULL,
    late_pct             DECIMAL(5, 1)  NULL,
    avg_delivery_days    DECIMAL(5, 1)  NULL,
    avg_review_score     DECIMAL(3, 2)  NULL,
    late_rate_decile     INT            NULL,      -- 1 = latest tenth; NULL below 50 single-seller orders
    CONSTRAINT pk_seller_performance PRIMARY KEY (seller_id)
);

DROP TABLE IF EXISTS mart.customer_summary;
CREATE TABLE mart.customer_summary (
    customer_unique_id        CHAR(32)       NOT NULL,
    current_state             CHAR(2)        NOT NULL,
    region                    VARCHAR(15)    NOT NULL,
    locations                 INT            NOT NULL,  -- versions in the customer history
    orders                    INT            NOT NULL,  -- any status
    delivered_orders          INT            NOT NULL,
    revenue                   DECIMAL(14, 2) NOT NULL,
    first_delivered_order_at  DATETIME2(0)   NULL,
    last_delivered_order_at   DATETIME2(0)   NULL,
    is_repeat                 BIT            NOT NULL,  -- 2 or more delivered orders
    second_order_same_day     BIT            NULL,      -- 1 = probably a split basket, not a return
    days_to_second_order      INT            NULL,
    first_order_review_score  INT            NULL,
    first_order_was_late      BIT            NULL,
    CONSTRAINT pk_customer_summary PRIMARY KEY (customer_unique_id)
);

DROP TABLE IF EXISTS mart.delivery_review;
CREATE TABLE mart.delivery_review (
    sort_order       INT           NOT NULL,
    arrival          VARCHAR(30)   NOT NULL,  -- how early or late against the estimated date
    orders           INT           NOT NULL,  -- delivered, with a delivery date and a review
    review_score_sum INT           NOT NULL,
    one_star_orders  INT           NOT NULL,
    five_star_orders INT           NOT NULL,
    avg_review_score DECIMAL(3, 2) NOT NULL,
    one_star_pct     DECIMAL(5, 1) NOT NULL,
    five_star_pct    DECIMAL(5, 1) NOT NULL,
    CONSTRAINT pk_delivery_review PRIMARY KEY (sort_order)
);
GO
