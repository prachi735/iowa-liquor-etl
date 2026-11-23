-- Q3: do top product lines grow by reaching more stores or by selling more per store.
-- litres = stores_ordering x liters_per_store, so growth splits into distribution and velocity.
TRUNCATE marts.product_line_month;
INSERT INTO marts.product_line_month
SELECT date_trunc('month', f.ordered_on)::date                          AS month,
       coalesce(i.product_line, 'Unknown')                              AS product_line,
       coalesce(c.category_group, 'Unmapped')                           AS category_group,
       count(DISTINCT f.store_no) FILTER (WHERE f.bottles > 0)          AS stores_ordering,
       sum(f.liters)                                                    AS liters,
       sum(f.dollars)                                                   AS dollars,
       round(sum(f.liters) / nullif(count(DISTINCT f.store_no) FILTER (WHERE f.bottles > 0), 0), 3)
                                                                        AS liters_per_store
FROM core.fact_sales f
JOIN core.dim_item i ON i.item_sk = f.item_sk
LEFT JOIN core.dim_category c ON c.category_code = f.category_code
GROUP BY 1, 2, 3
ORDER BY 1, dollars DESC;
