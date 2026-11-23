-- Q6: how concentrated spend is across stores, and whether chains gain on independents.
TRUNCATE marts.store_year;
INSERT INTO marts.store_year
SELECT y.*,
       round(dollars / nullif(sum(dollars) OVER (PARTITION BY year), 0), 6)   AS dollar_share,
       rank() OVER (PARTITION BY year ORDER BY dollars DESC)                  AS dollar_rank,
       round(cume_dist() OVER (PARTITION BY year ORDER BY dollars)::numeric, 4) AS dollar_percentile
FROM (
    SELECT extract(year FROM f.ordered_on)::int AS year,
           f.store_no,
           s.store_name, s.store_city, s.chain, s.store_type,
           sum(f.dollars) AS dollars,
           sum(f.liters)  AS liters,
           count(DISTINCT f.invoice_id) AS invoices
    FROM core.fact_sales f
    JOIN core.dim_store s ON s.store_no = f.store_no AND s.is_current
    GROUP BY 1, 2, 3, 4, 5, 6
) y
ORDER BY year, dollars DESC;
