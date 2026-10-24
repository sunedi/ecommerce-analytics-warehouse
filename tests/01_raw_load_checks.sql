/*
Checks that the latest raw load is complete.

1. Every file in the manifest was loaded successfully in the latest batch.
2. Every raw table holds exactly as many rows as the source file has records
   (counted independently by scripts/get_data.py with Python's CSV parser).

Returns one row per check, then raises an error if any check failed so that
build.ps1 stops.
*/
USE EcommerceDW;
GO

SET NOCOUNT ON;

DROP TABLE IF EXISTS #results;

WITH latest_batch AS (
    SELECT file_name, status, rows_loaded
    FROM audit.load_log
    WHERE batch_id = (SELECT MAX(batch_id) FROM audit.load_log)
),
table_rows AS (
    SELECT N'olist_customers_dataset.csv' AS file_name, COUNT_BIG(*) AS table_rows FROM raw.olist_customers
    UNION ALL SELECT N'olist_geolocation_dataset.csv',         COUNT_BIG(*) FROM raw.olist_geolocation
    UNION ALL SELECT N'olist_order_items_dataset.csv',         COUNT_BIG(*) FROM raw.olist_order_items
    UNION ALL SELECT N'olist_order_payments_dataset.csv',      COUNT_BIG(*) FROM raw.olist_order_payments
    UNION ALL SELECT N'olist_order_reviews_dataset.csv',       COUNT_BIG(*) FROM raw.olist_order_reviews
    UNION ALL SELECT N'olist_orders_dataset.csv',              COUNT_BIG(*) FROM raw.olist_orders
    UNION ALL SELECT N'olist_products_dataset.csv',            COUNT_BIG(*) FROM raw.olist_products
    UNION ALL SELECT N'olist_sellers_dataset.csv',             COUNT_BIG(*) FROM raw.olist_sellers
    UNION ALL SELECT N'product_category_name_translation.csv', COUNT_BIG(*) FROM raw.product_category_name_translation
)
-- FULL OUTER JOIN so that a file missing from either side still shows up as a failure
SELECT
    COALESCE(m.file_name, t.file_name) AS file_name,
    m.record_count                     AS expected_records,
    t.table_rows,
    b.status                           AS load_status,
    CASE
        WHEN m.file_name IS NULL                 THEN 'FAIL: table has no manifest entry'
        WHEN t.file_name IS NULL                 THEN 'FAIL: no raw table for this file'
        WHEN ISNULL(b.status, '') <> 'succeeded' THEN 'FAIL: not loaded in latest batch'
        WHEN t.table_rows <> m.record_count      THEN 'FAIL: row count differs'
        ELSE 'PASS'
    END AS result
INTO #results
FROM audit.source_manifest AS m
FULL OUTER JOIN table_rows AS t
    ON t.file_name = m.file_name
LEFT JOIN latest_batch AS b
    ON b.file_name = COALESCE(m.file_name, t.file_name);

SELECT file_name, expected_records, table_rows, load_status, result
FROM #results
ORDER BY file_name;

IF EXISTS (SELECT 1 FROM #results WHERE result <> 'PASS')
    THROW 50001, 'Raw load checks failed. See the results above.', 1;

PRINT 'All raw load checks passed.';
GO
