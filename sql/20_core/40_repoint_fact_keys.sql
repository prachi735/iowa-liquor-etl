-- When this batch added a dimension version that starts inside dates already loaded
-- (for example a store rename that shows up in a later file), move those older fact rows
-- to the version that is now valid on their order date.

UPDATE core.fact_sales f
SET store_sk = d.store_sk
FROM core.dim_store d
WHERE d.store_no = f.store_no
  AND f.ordered_on BETWEEN d.valid_from AND d.valid_to
  AND f.store_sk IS DISTINCT FROM d.store_sk
  AND f.store_no IN (SELECT store_no FROM core.dim_store
                     WHERE batch_id = current_setting('pipeline.batch_id')::bigint
                       AND valid_from > DATE '1900-01-01');

UPDATE core.fact_sales f
SET item_sk = d.item_sk
FROM core.dim_item d
WHERE d.item_no = f.item_no
  AND f.ordered_on BETWEEN d.valid_from AND d.valid_to
  AND f.item_sk IS DISTINCT FROM d.item_sk
  AND f.item_no IN (SELECT item_no FROM core.dim_item
                    WHERE batch_id = current_setting('pipeline.batch_id')::bigint
                      AND valid_from > DATE '1900-01-01');

UPDATE core.fact_sales f
SET vendor_sk = d.vendor_sk
FROM core.dim_vendor d
WHERE d.vendor_no = f.vendor_no
  AND f.ordered_on BETWEEN d.valid_from AND d.valid_to
  AND f.vendor_sk IS DISTINCT FROM d.vendor_sk
  AND f.vendor_no IN (SELECT vendor_no FROM core.dim_vendor
                      WHERE batch_id = current_setting('pipeline.batch_id')::bigint
                        AND valid_from > DATE '1900-01-01');
