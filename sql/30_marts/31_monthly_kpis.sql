-- Headline numbers per month. Dollars are net of returns.
TRUNCATE marts.monthly_kpis;
INSERT INTO marts.monthly_kpis
SELECT date_trunc('month', f.ordered_on)::date                     AS month,
       sum(f.dollars)                                              AS dollars,
       sum(f.liters)                                               AS liters,
       sum(f.bottles)                                              AS bottles,
       count(DISTINCT f.invoice_id)                                AS invoices,
       count(DISTINCT f.store_no)                                  AS stores_ordering,
       count(DISTINCT f.item_no)                                   AS items_ordered,
       coalesce(-sum(f.dollars) FILTER (WHERE f.is_return), 0)     AS return_dollars,
       round(sum(f.dollars) / nullif(sum(f.liters), 0), 2)         AS dollars_per_liter,
       count(DISTINCT f.ordered_on)                                AS order_days
FROM core.fact_sales f
GROUP BY 1
ORDER BY 1;
