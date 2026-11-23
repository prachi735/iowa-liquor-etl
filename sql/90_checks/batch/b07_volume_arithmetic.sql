-- Litres should equal bottles x bottle size / 1000.
SELECT 'litres = bottles x bottle size' AS check_name,
       'warning' AS severity,
       count(*) AS failed_rows,
       format('%s lines off by more than 0.01 L', count(*)) AS detail
FROM staging.liquor_sales
WHERE liters IS NOT NULL AND bottle_volume_ml IS NOT NULL
  AND abs(liters - bottles * bottle_volume_ml / 1000.0) > 0.01;
