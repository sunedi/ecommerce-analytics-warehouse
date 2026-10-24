/*
Question 5: Do payments reconcile to item prices plus freight for every order?

What a customer owes = item_total + freight_total. What they paid = payment_total.
Both are already summed to one row per order in fct_order, so comparing them can't
repeat any item or payment (docs/data_model.md, querying rules).

A difference of up to R$0.01 is treated as a match (rounding between instalments).
All orders are included, whatever their status, because reconciliation must account
for every payment, not only revenue.
*/
USE EcommerceDW;
GO

-- 1. Every order classified by how its payments compare with what was owed
WITH classified AS (
    SELECT
        order_id,
        order_status,
        payment_total,
        item_total + freight_total                 AS amount_due,
        payment_total - (item_total + freight_total) AS difference,
        CASE
            WHEN item_count = 0 AND payment_count = 0                       THEN '6. no items and no payment'
            WHEN item_count = 0                                             THEN '4. paid, but no items recorded'
            WHEN payment_count = 0                                          THEN '5. items, but no payment recorded'
            WHEN ABS(payment_total - (item_total + freight_total)) <= 0.01 THEN '1. matched'
            WHEN payment_total > item_total + freight_total                 THEN '2. paid more than due'
            ELSE                                                                 '3. paid less than due'
        END AS reconciliation_status
    FROM dw.fct_order
)
SELECT
    reconciliation_status,
    COUNT(*)                                                         AS orders,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5, 2))  AS pct_of_orders,
    SUM(amount_due)                                                  AS amount_due,
    SUM(payment_total)                                               AS amount_paid,
    SUM(difference)                                                  AS difference
FROM classified
GROUP BY reconciliation_status
ORDER BY reconciliation_status;

-- 2. Orders paid but with no items: which statuses are they in?
SELECT
    order_status,
    COUNT(*)           AS orders,
    SUM(payment_total) AS amount_paid
FROM dw.fct_order
WHERE item_count = 0
  AND payment_count > 0
GROUP BY order_status
ORDER BY orders DESC;

-- 3. Do overpayments come from instalments? Orders with items and payments, grouped by
-- the largest number of instalments used on any of their payments.
WITH order_instalments AS (
    SELECT order_id, MAX(payment_installments) AS max_instalments
    FROM dw.fct_payment
    GROUP BY order_id
),
compared AS (
    SELECT
        CASE
            WHEN i.max_instalments <= 1  THEN '1. single payment'
            WHEN i.max_instalments <= 5  THEN '2. 2-5 instalments'
            WHEN i.max_instalments <= 10 THEN '3. 6-10 instalments'
            ELSE                              '4. 11+ instalments'
        END AS instalments,
        o.payment_total - (o.item_total + o.freight_total) AS difference,
        o.item_total + o.freight_total                     AS amount_due
    FROM dw.fct_order AS o
    INNER JOIN order_instalments AS i
        ON i.order_id = o.order_id
    WHERE o.item_count > 0
)
SELECT
    instalments,
    COUNT(*)                                                                         AS orders,
    SUM(CASE WHEN difference > 0.01 THEN 1 ELSE 0 END)                               AS overpaid_orders,
    CAST(100.0 * SUM(CASE WHEN difference > 0.01 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5, 2)) AS overpaid_pct,
    -- How much more than due the overpaid orders paid, relative to what they owed
    CAST(100.0 * SUM(CASE WHEN difference > 0.01 THEN difference END)
         / NULLIF(SUM(CASE WHEN difference > 0.01 THEN amount_due END), 0) AS DECIMAL(5, 1)) AS overpaid_by_pct
FROM compared
GROUP BY instalments
ORDER BY instalments;

-- 4. Exception list for follow-up: the 10 largest differences on orders that have items
SELECT TOP (10)
    o.order_id,
    o.order_status,
    o.item_total + o.freight_total                     AS amount_due,
    o.payment_total                                    AS amount_paid,
    o.payment_total - (o.item_total + o.freight_total) AS difference,
    o.payment_count
FROM dw.fct_order AS o
WHERE o.item_count > 0
  AND ABS(o.payment_total - (o.item_total + o.freight_total)) > 0.01
ORDER BY ABS(o.payment_total - (o.item_total + o.freight_total)) DESC;
