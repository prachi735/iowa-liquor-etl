-- Category codes with no rule in core.category_group_rule land in 'Unmapped'.
SELECT 'category codes mapped to a group' AS check_name,
       'warning' AS severity,
       count(*) AS failed_rows,
       coalesce('unmapped: ' || string_agg(category_code || ' ' || coalesce(category_name, ''), ', '),
                'all codes mapped') AS detail
FROM core.dim_category
WHERE category_group = 'Unmapped'
  AND category_code IN (SELECT DISTINCT category_code FROM staging.liquor_sales);
