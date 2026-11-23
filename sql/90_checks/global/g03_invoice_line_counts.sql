-- The invoice table and the fact table must agree on lines and dollars.
WITH lines AS (
    SELECT invoice_id, count(*) AS n, sum(dollars) AS dollars FROM core.fact_sales GROUP BY invoice_id
)
SELECT 'invoice totals = fact totals' AS check_name,
       'error' AS severity,
       count(*) AS failed_rows,
       format('%s invoices disagree', count(*)) AS detail
FROM core.invoice i
FULL JOIN lines l USING (invoice_id)
WHERE (i.deleted_batch_id IS NULL AND (l.invoice_id IS NULL OR l.n <> i.line_count OR l.dollars <> i.dollars))
   OR (i.deleted_batch_id IS NOT NULL AND l.invoice_id IS NOT NULL)
   OR i.invoice_id IS NULL;
