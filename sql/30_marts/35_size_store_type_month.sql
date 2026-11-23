-- Q4: are small bottles gaining, and in which kind of store.
TRUNCATE marts.size_store_type_month;
INSERT INTO marts.size_store_type_month
SELECT date_trunc('month', f.ordered_on)::date AS month,
       coalesce(i.size_band, 'Unknown')        AS size_band,
       coalesce(s.store_type, 'Other')         AS store_type,
       sum(f.bottles) AS bottles,
       sum(f.liters)  AS liters,
       sum(f.dollars) AS dollars
FROM core.fact_sales f
JOIN core.dim_item  i ON i.item_sk  = f.item_sk
JOIN core.dim_store s ON s.store_sk = f.store_sk
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
