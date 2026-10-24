/*
Who are the customers, and where are they?

customer_id is created fresh for every order; customer_unique_id identifies
the person. Locations come from ZIP code prefixes, which the geolocation
table lists many times over.
*/
USE EcommerceDW;
GO

-- 1. How many orders does each real customer place?
WITH orders_per_customer AS (
    SELECT c.customer_unique_id, COUNT(*) AS orders
    FROM stg.orders AS o
    INNER JOIN stg.customers AS c
        ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
)
SELECT
    CASE WHEN orders >= 4 THEN '4+' ELSE CAST(orders AS VARCHAR(2)) END AS orders_placed,
    COUNT(*)                                                             AS customers,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5, 2))      AS pct_of_customers
FROM orders_per_customer
GROUP BY CASE WHEN orders >= 4 THEN '4+' ELSE CAST(orders AS VARCHAR(2)) END
ORDER BY orders_placed;

-- 2. Do customers keep the same location across orders?
SELECT
    COUNT(*)                                                       AS customers_with_several_orders,
    SUM(CASE WHEN zip_prefixes > 1 THEN 1 ELSE 0 END)              AS changed_zip_prefix,
    SUM(CASE WHEN states > 1 THEN 1 ELSE 0 END)                    AS changed_state
FROM (
    SELECT customer_unique_id,
           COUNT(DISTINCT customer_zip_code_prefix) AS zip_prefixes,
           COUNT(DISTINCT customer_state)           AS states
    FROM stg.customers
    GROUP BY customer_unique_id
    HAVING COUNT(*) > 1
) AS repeat_customers;

-- 3. Geolocation: how many rows, cities and states share one ZIP prefix?
SELECT
    COUNT(*)                                              AS zip_prefixes,
    AVG(CAST(rows_per_prefix AS DECIMAL(10, 1)))          AS avg_rows_per_prefix,
    MAX(rows_per_prefix)                                  AS max_rows_per_prefix,
    SUM(CASE WHEN states > 1 THEN 1 ELSE 0 END)           AS prefixes_in_several_states,
    SUM(CASE WHEN cities > 1 THEN 1 ELSE 0 END)           AS prefixes_with_several_city_spellings
FROM (
    SELECT geolocation_zip_code_prefix,
           COUNT(*)                          AS rows_per_prefix,
           COUNT(DISTINCT geolocation_state) AS states,
           COUNT(DISTINCT geolocation_city)  AS cities
    FROM stg.geolocation
    GROUP BY geolocation_zip_code_prefix
) AS per_prefix;

-- 4. Example of inconsistent city spellings within one ZIP prefix
SELECT TOP (10) geolocation_zip_code_prefix, geolocation_city, COUNT(*) AS rows
FROM stg.geolocation
WHERE geolocation_zip_code_prefix = '01001'
GROUP BY geolocation_zip_code_prefix, geolocation_city
ORDER BY rows DESC;
