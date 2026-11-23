-- Q2: does spend move to higher price tiers. Price per 750 ml equivalent at the state's
-- price to stores (shelf prices are higher). Tier bands follow the usual industry split.
TRUNCATE marts.price_tier_month;
INSERT INTO marts.price_tier_month
SELECT date_trunc('month', f.ordered_on)::date AS month,
       coalesce(c.category_group, 'Unmapped') AS category_group,
       CASE WHEN p.price_750 IS NULL THEN 'Unknown'
            WHEN p.price_750 < 12   THEN '1 Value (under $12)'
            WHEN p.price_750 < 17   THEN '2 Premium ($12-17)'
            WHEN p.price_750 < 30   THEN '3 High-end ($17-30)'
            ELSE                         '4 Super-premium ($30+)' END AS price_tier,
       sum(f.dollars)  AS dollars,
       sum(f.liters)   AS liters,
       sum(f.bottles)  AS bottles
FROM core.fact_sales f
JOIN core.dim_item i ON i.item_sk = f.item_sk
LEFT JOIN core.dim_category c ON c.category_code = f.category_code
CROSS JOIN LATERAL (SELECT f.unit_price * 750 / nullif(i.bottle_volume_ml, 0) AS price_750) p
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
