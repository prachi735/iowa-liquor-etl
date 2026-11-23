-- Q1: which categories gain share of dollars and litres.
TRUNCATE marts.category_month;
INSERT INTO marts.category_month
SELECT x.*,
       round(dollars / nullif(sum(dollars) OVER (PARTITION BY month), 0), 4) AS dollar_share,
       round(liters  / nullif(sum(liters)  OVER (PARTITION BY month), 0), 4) AS liter_share
FROM (
    SELECT date_trunc('month', f.ordered_on)::date       AS month,
           coalesce(c.category_group, 'Unmapped')       AS category_group,
           sum(f.dollars)                                AS dollars,
           sum(f.liters)                                 AS liters,
           sum(f.bottles)                                AS bottles
    FROM core.fact_sales f
    LEFT JOIN core.dim_category c ON c.category_code = f.category_code
    GROUP BY 1, 2
) x
ORDER BY month, category_group;
