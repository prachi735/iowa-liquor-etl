-- Q5: how many new items are still ordered a year after launch.
-- An item counts as launched when its first order is at least 3 months after the data starts,
-- and is judged only once 12 months have passed since its first order.
TRUNCATE marts.item_lifecycle;
INSERT INTO marts.item_lifecycle
WITH bounds AS (
    SELECT date_trunc('month', min(ordered_on))::date AS data_start,
           date_trunc('month', max(ordered_on))::date AS data_end
    FROM core.fact_sales
), item_months AS (
    SELECT item_no,
           date_trunc('month', ordered_on)::date AS month,
           sum(liters) AS liters, sum(dollars) AS dollars
    FROM core.fact_sales
    WHERE bottles > 0
    GROUP BY 1, 2
), life AS (
    SELECT item_no, min(month) AS first_month, max(month) AS last_month, count(*) AS months_with_orders
    FROM item_months GROUP BY item_no
), first_year AS (
    SELECT m.item_no, sum(m.liters) AS liters, sum(m.dollars) AS dollars
    FROM item_months m
    JOIN life l USING (item_no)
    WHERE m.month < l.first_month + interval '12 months'
    GROUP BY m.item_no
)
SELECT l.item_no,
       i.item_desc, i.product_line, i.size_band,
       coalesce(c.category_group, 'Unmapped')                         AS category_group,
       l.first_month, l.last_month, l.months_with_orders,
       l.first_month >= b.data_start + interval '3 months'            AS is_launch,
       l.first_month <= b.data_end - interval '12 months'             AS has_12_months_history,
       l.last_month  >= l.first_month + interval '12 months'          AS ordered_after_12_months,
       fy.liters                                                      AS liters_first_12_months,
       fy.dollars                                                     AS dollars_first_12_months
FROM life l
CROSS JOIN bounds b
JOIN first_year fy USING (item_no)
JOIN core.dim_item i ON i.item_no = l.item_no AND i.is_current
LEFT JOIN core.dim_category c ON c.category_code = i.category_code;
