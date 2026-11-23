-- After the merge, every invoice in the file must hold exactly the file's lines and dollars.
WITH file AS (
    SELECT invoice_id, count(*) AS lines, sum(dollars) AS dollars
    FROM staging.liquor_sales GROUP BY invoice_id
), fact AS (
    SELECT f.invoice_id, count(*) AS lines, sum(f.dollars) AS dollars
    FROM core.fact_sales f
    WHERE f.invoice_id IN (SELECT invoice_id FROM file)
    GROUP BY f.invoice_id
)
SELECT 'fact matches file, invoice by invoice' AS check_name,
       'error' AS severity,
       count(*) FILTER (WHERE fact.invoice_id IS NULL OR fact.lines <> file.lines
                        OR fact.dollars <> file.dollars) AS failed_rows,
       format('%s invoices, %s lines, $%s in the file', count(*), sum(file.lines),
              to_char(sum(file.dollars), 'FM999,999,999,990.00')) AS detail
FROM file LEFT JOIN fact USING (invoice_id);
