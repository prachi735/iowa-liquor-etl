-- Invoices dropped because a file covering their date no longer has them.
-- Many at once usually means a truncated download, not real deletions, so stop above
-- 2% of the window (and more than 10 invoices).
SELECT 'invoices deleted by this file' AS check_name,
       CASE WHEN d.n > greatest(10, 0.02 * w.n) THEN 'error' ELSE 'warning' END AS severity,
       d.n AS failed_rows,
       format('%s of %s invoices in the date window', d.n, w.n) AS detail
FROM (SELECT count(*) AS n FROM core.invoice
      WHERE deleted_batch_id = current_setting('pipeline.batch_id')::bigint) d,
     (SELECT count(*) AS n FROM core.invoice i
      WHERE i.ordered_on BETWEEN (SELECT min(ordered_on) FROM staging.liquor_sales)
                             AND (SELECT max(ordered_on) FROM staging.liquor_sales)) w;
