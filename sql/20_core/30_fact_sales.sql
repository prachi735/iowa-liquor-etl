-- Sales fact, loaded invoice by invoice.
-- In recent files invoice_id names a whole invoice (about 11 lines; older files used one id
-- per line) and no line number is published. So the invoice is the unit of change:
--   new        not seen before                         -> insert its lines
--   changed    seen, but its lines hash differently    -> replace its lines
--   restored   seen and marked deleted, now back       -> insert its lines again
--   unchanged  same hash                               -> nothing to do
--   deleted    in core, dated inside this file's date window, missing from the file
--              -> remove its lines, keep the invoice row with deleted_batch_id for audit
--   id_reused  same id, order date more than 60 days away -> batch check b12 stops the load
-- Re-loading the same data therefore changes nothing.

CREATE TEMP TABLE _inv ON COMMIT DROP AS
SELECT invoice_id,
       min(ordered_on)                                    AS ordered_on,
       min(store_no)                                      AS store_no,
       count(*)::int                                      AS line_count,
       sum(dollars)                                       AS dollars,
       bool_or(is_return)                                 AS is_return,
       md5(string_agg(line_hash, '' ORDER BY line_hash))  AS invoice_hash
FROM staging.liquor_sales
GROUP BY invoice_id;

CREATE TEMP TABLE _inv_action ON COMMIT DROP AS
SELECT b.invoice_id,
       CASE WHEN c.invoice_id IS NULL             THEN 'new'
            -- the same id on a date far from the one already stored: probably a reused
            -- number, not an edit; check b12 stops the batch so no history is overwritten
            WHEN abs(c.ordered_on - b.ordered_on) > 60 THEN 'id_reused'
            WHEN c.deleted_batch_id IS NOT NULL   THEN 'restored'
            WHEN c.invoice_hash <> b.invoice_hash THEN 'changed'
            ELSE 'unchanged' END AS action
FROM _inv b
LEFT JOIN core.invoice c USING (invoice_id)
UNION ALL
SELECT c.invoice_id, 'deleted'
FROM core.invoice c
WHERE c.deleted_batch_id IS NULL
  AND c.ordered_on BETWEEN (SELECT min(ordered_on) FROM staging.liquor_sales)
                       AND (SELECT max(ordered_on) FROM staging.liquor_sales)
  AND NOT EXISTS (SELECT 1 FROM _inv b WHERE b.invoice_id = c.invoice_id);

CREATE INDEX ON _inv_action (invoice_id);
ANALYZE _inv_action;

-- Remove lines of invoices that changed or disappeared.
DELETE FROM core.fact_sales f
USING _inv_action a
WHERE f.invoice_id = a.invoice_id AND a.action IN ('changed', 'deleted');

UPDATE core.invoice c
SET deleted_batch_id = current_setting('pipeline.batch_id')::bigint
FROM _inv_action a
WHERE a.invoice_id = c.invoice_id AND a.action = 'deleted';

-- Upsert the invoice rows that are in this file.
INSERT INTO core.invoice AS c (invoice_id, ordered_on, store_no, line_count, dollars, is_return,
                               invoice_hash, first_batch_id, last_batch_id)
SELECT b.invoice_id, b.ordered_on, b.store_no, b.line_count, b.dollars, b.is_return, b.invoice_hash,
       current_setting('pipeline.batch_id')::bigint, current_setting('pipeline.batch_id')::bigint
FROM _inv b
ON CONFLICT (invoice_id) DO UPDATE SET
    changed_batch_id = CASE WHEN c.invoice_hash <> EXCLUDED.invoice_hash OR c.deleted_batch_id IS NOT NULL
                            THEN EXCLUDED.last_batch_id ELSE c.changed_batch_id END,
    ordered_on       = EXCLUDED.ordered_on,
    store_no         = EXCLUDED.store_no,
    line_count       = EXCLUDED.line_count,
    dollars          = EXCLUDED.dollars,
    is_return        = EXCLUDED.is_return,
    invoice_hash     = EXCLUDED.invoice_hash,
    last_batch_id    = EXCLUDED.last_batch_id,
    deleted_batch_id = NULL;

-- Insert lines of new, changed and restored invoices, linked to the dimension version
-- that was valid on the order date.
INSERT INTO core.fact_sales (invoice_id, line_seq, ordered_on, store_no, item_no, vendor_no, category_code,
                             store_sk, item_sk, vendor_sk, bottles, dollars, liters, list_retail, list_cost,
                             unit_price, is_return, line_hash, batch_id)
SELECT s.invoice_id, s.line_seq, s.ordered_on, s.store_no, s.item_no, s.vendor_no, s.category_code,
       ds.store_sk, di.item_sk, dv.vendor_sk,
       s.bottles, s.dollars, s.liters, s.list_retail, s.list_cost, s.unit_price, s.is_return, s.line_hash,
       current_setting('pipeline.batch_id')::bigint
FROM staging.liquor_sales s
JOIN _inv_action a ON a.invoice_id = s.invoice_id AND a.action IN ('new', 'changed', 'restored')
LEFT JOIN core.dim_store  ds ON ds.store_no  = s.store_no  AND s.ordered_on BETWEEN ds.valid_from AND ds.valid_to
LEFT JOIN core.dim_item   di ON di.item_no   = s.item_no   AND s.ordered_on BETWEEN di.valid_from AND di.valid_to
LEFT JOIN core.dim_vendor dv ON dv.vendor_no = s.vendor_no AND s.ordered_on BETWEEN dv.valid_from AND dv.valid_to;
