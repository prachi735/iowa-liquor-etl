-- Categories: keep the latest name per code. The group is set in sql/25_rules.

INSERT INTO core.dim_category AS c (category_code, category_name, first_seen_on, last_seen_on)
SELECT DISTINCT ON (category_code)
    category_code,
    category_name,
    min(ordered_on) OVER (PARTITION BY category_code),
    max(ordered_on) OVER (PARTITION BY category_code)
FROM staging.liquor_sales
WHERE category_code IS NOT NULL
ORDER BY category_code, ordered_on DESC, row_no DESC
ON CONFLICT (category_code) DO UPDATE SET
    category_name = CASE WHEN EXCLUDED.last_seen_on >= c.last_seen_on
                         THEN coalesce(EXCLUDED.category_name, c.category_name)
                         ELSE c.category_name END,
    first_seen_on = least(c.first_seen_on, EXCLUDED.first_seen_on),
    last_seen_on  = greatest(c.last_seen_on, EXCLUDED.last_seen_on);
