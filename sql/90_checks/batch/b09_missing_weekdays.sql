-- Orders arrive Monday to Friday. A weekday with no lines inside the window may be a
-- state holiday, or a gap in the source file.
SELECT 'weekdays with orders' AS check_name,
       'warning' AS severity,
       count(*) AS failed_rows,
       coalesce('no orders on ' || string_agg(to_char(d, 'Dy DD Mon YYYY'), ', ' ORDER BY d),
                'every weekday in the window has orders') AS detail
FROM generate_series((SELECT min(ordered_on) FROM staging.liquor_sales),
                     (SELECT max(ordered_on) FROM staging.liquor_sales), interval '1 day') AS g(d)
WHERE extract(isodow FROM d) < 6
  AND NOT EXISTS (SELECT 1 FROM staging.liquor_sales s WHERE s.ordered_on = d::date);
