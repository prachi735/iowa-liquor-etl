-- Every fact line must link to a store and an item version.
SELECT 'fact lines linked to store and item' AS check_name,
       'error' AS severity,
       count(*) AS failed_rows,
       format('%s lines without a store or item version', count(*)) AS detail
FROM core.fact_sales
WHERE store_sk IS NULL OR item_sk IS NULL;
