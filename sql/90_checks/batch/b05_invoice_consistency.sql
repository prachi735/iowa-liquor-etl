-- One invoice should belong to one store and one order date.
SELECT 'invoices with one store and one date' AS check_name,
       'warning' AS severity,
       count(*) AS failed_rows,
       format('%s invoices span more than one store or date', count(*)) AS detail
FROM (SELECT invoice_id FROM staging.liquor_sales
      GROUP BY invoice_id
      HAVING count(DISTINCT store_no) > 1 OR count(DISTINCT ordered_on) > 1) x;
