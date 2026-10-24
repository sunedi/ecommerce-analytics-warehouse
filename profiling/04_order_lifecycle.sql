/*
Do order timestamps and statuses tell a consistent story?

An order should move purchase -> approved -> handed to carrier -> delivered to customer,
and its status should match the timestamps it has.
*/
USE EcommerceDW;
GO

-- 1. Which timestamps does each status have? (count of orders with the timestamp filled in)
SELECT
    order_status,
    COUNT(*)                              AS orders,
    COUNT(order_approved_at)              AS has_approved,
    COUNT(order_delivered_carrier_date)   AS has_carrier,
    COUNT(order_delivered_customer_date)  AS has_delivered
FROM stg.orders
GROUP BY order_status
ORDER BY orders DESC;

-- 2. Timestamps in an impossible order
SELECT rule_broken, orders
FROM (
    SELECT 1 AS sort_order, 'approved before purchase' AS rule_broken,
           (SELECT COUNT(*) FROM stg.orders WHERE order_approved_at < order_purchase_timestamp) AS orders
    UNION ALL
    SELECT 2, 'handed to carrier before purchase',
           (SELECT COUNT(*) FROM stg.orders WHERE order_delivered_carrier_date < order_purchase_timestamp)
    UNION ALL
    SELECT 3, 'handed to carrier before approval',
           (SELECT COUNT(*) FROM stg.orders WHERE order_delivered_carrier_date < order_approved_at)
    UNION ALL
    SELECT 4, 'delivered before purchase',
           (SELECT COUNT(*) FROM stg.orders WHERE order_delivered_customer_date < order_purchase_timestamp)
    UNION ALL
    SELECT 5, 'delivered before handed to carrier',
           (SELECT COUNT(*) FROM stg.orders WHERE order_delivered_customer_date < order_delivered_carrier_date)
    UNION ALL
    SELECT 6, 'estimated delivery before purchase date',
           (SELECT COUNT(*) FROM stg.orders WHERE order_estimated_delivery_date < CAST(order_purchase_timestamp AS DATE))
    UNION ALL
    -- An order can break several rules, so this is less than the sum of the rows above
    SELECT 7, 'any of the above (distinct orders)',
           (SELECT COUNT(*) FROM stg.orders
            WHERE order_approved_at < order_purchase_timestamp
               OR order_delivered_carrier_date < order_purchase_timestamp
               OR order_delivered_carrier_date < order_approved_at
               OR order_delivered_customer_date < order_purchase_timestamp
               OR order_delivered_customer_date < order_delivered_carrier_date
               OR order_estimated_delivery_date < CAST(order_purchase_timestamp AS DATE))
) AS rules
ORDER BY sort_order;

-- 3. Status and timestamps that contradict each other
SELECT
    SUM(CASE WHEN order_status = 'delivered'  AND order_delivered_customer_date IS NULL     THEN 1 ELSE 0 END) AS delivered_without_delivery_date,
    SUM(CASE WHEN order_status <> 'delivered' AND order_delivered_customer_date IS NOT NULL THEN 1 ELSE 0 END) AS delivery_date_but_not_delivered,
    SUM(CASE WHEN order_status = 'canceled'   AND order_delivered_customer_date IS NOT NULL THEN 1 ELSE 0 END) AS canceled_after_delivery
FROM stg.orders;

-- 4. Orders per purchase month: are the first and last months complete?
SELECT
    DATEFROMPARTS(YEAR(order_purchase_timestamp), MONTH(order_purchase_timestamp), 1) AS purchase_month,
    COUNT(*)                                                                         AS orders,
    MIN(order_purchase_timestamp)                                                    AS first_order,
    MAX(order_purchase_timestamp)                                                    AS last_order
FROM stg.orders
GROUP BY DATEFROMPARTS(YEAR(order_purchase_timestamp), MONTH(order_purchase_timestamp), 1)
ORDER BY purchase_month;
