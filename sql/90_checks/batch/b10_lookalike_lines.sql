-- Same store, date, item, bottles and dollars on two different invoices. Often two real
-- orders, sometimes a double entry: counted for review, never deleted.
SELECT 'look-alike lines on different invoices' AS check_name,
       'info' AS severity,
       coalesce(sum(n - 1), 0) AS failed_rows,
       format('%s groups of identical lines across invoices', count(*)) AS detail
FROM (SELECT count(DISTINCT invoice_id) AS n
      FROM staging.liquor_sales
      WHERE NOT is_return
      GROUP BY store_no, ordered_on, item_no, bottles, dollars
      HAVING count(DISTINCT invoice_id) > 1) x;
