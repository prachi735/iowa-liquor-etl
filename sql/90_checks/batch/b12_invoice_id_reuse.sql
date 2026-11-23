-- An invoice id already stored with an order date more than 60 days away is probably a
-- reused number. Merging it would overwrite the older invoice, so the batch stops.
-- Reads _inv_action, the classification table built by sql/20_core/30_fact_sales.sql.
SELECT 'invoice ids not reused across dates' AS check_name,
       'error' AS severity,
       count(*) AS failed_rows,
       coalesce('reused: ' || string_agg(invoice_id, ', ' ORDER BY invoice_id) FILTER (WHERE rn <= 5),
                'no id clashes with older invoices') AS detail
FROM (SELECT invoice_id, row_number() OVER (ORDER BY invoice_id) AS rn
      FROM _inv_action WHERE action = 'id_reused') x;
