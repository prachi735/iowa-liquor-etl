-- Dollars should equal bottles x list price. About 0.7% of lines differ (the list price
-- column seems to show a different month's price), so this only warns above 5%.
SELECT 'dollars = bottles x list price' AS check_name,
       CASE WHEN count(*) FILTER (WHERE off) > 0.05 * greatest(count(*), 1) THEN 'warning' ELSE 'info' END AS severity,
       count(*) FILTER (WHERE off) AS failed_rows,
       format('%s of %s priced lines differ by more than 1%% (unit price uses dollars / bottles)',
              count(*) FILTER (WHERE off), count(*)) AS detail
FROM (SELECT abs(dollars - bottles * list_retail) > greatest(0.01, 0.01 * abs(dollars)) AS off
      FROM staging.liquor_sales WHERE list_retail IS NOT NULL) x;
