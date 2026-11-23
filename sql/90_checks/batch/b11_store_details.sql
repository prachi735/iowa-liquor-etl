-- Lines from stores with no address, city or county in the file.
SELECT 'store details present' AS check_name,
       'info' AS severity,
       count(*) AS failed_rows,
       format('%s lines from %s stores without city or county', count(*), count(DISTINCT store_no)) AS detail
FROM staging.liquor_sales
WHERE store_city IS NULL OR county_name IS NULL;
