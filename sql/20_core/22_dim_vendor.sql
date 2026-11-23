-- Vendor dimension, type 2: a new version when the vendor name changes (renames, acquisitions).
-- Same pattern as dim_store; see that file for the step-by-step comments.

CREATE TEMP TABLE _vendor_obs ON COMMIT DROP AS
SELECT DISTINCT ON (vendor_no, ordered_on) vendor_no, ordered_on, vendor_name, vendor_hash AS attr_hash
FROM staging.liquor_sales
WHERE vendor_no IS NOT NULL
ORDER BY vendor_no, ordered_on, row_no DESC;

CREATE TEMP TABLE _vendor_ver ON COMMIT DROP AS
SELECT DISTINCT ON (vendor_no, island) vendor_no, ordered_on AS seen_from, vendor_name, attr_hash
FROM (
    SELECT o.*, sum(changed) OVER (PARTITION BY vendor_no ORDER BY ordered_on) AS island
    FROM (SELECT o.*, (attr_hash IS DISTINCT FROM lag(attr_hash) OVER (PARTITION BY vendor_no ORDER BY ordered_on))::int AS changed
          FROM _vendor_obs o) o
) x
ORDER BY vendor_no, island, ordered_on;

CREATE TEMP TABLE _vendor_new ON COMMIT DROP AS
SELECT v.*, row_number() OVER (PARTITION BY v.vendor_no ORDER BY v.seen_from) AS rn
FROM _vendor_ver v
LEFT JOIN core.dim_vendor c ON c.vendor_no = v.vendor_no AND c.is_current
WHERE c.vendor_sk IS NULL OR v.seen_from > c.first_seen_on;

DELETE FROM _vendor_new n
USING core.dim_vendor c
WHERE n.rn = 1 AND c.vendor_no = n.vendor_no AND c.is_current AND c.attr_hash = n.attr_hash;

UPDATE core.dim_vendor c
SET valid_to = n.first_from - 1, is_current = false
FROM (SELECT vendor_no, min(seen_from) AS first_from FROM _vendor_new GROUP BY vendor_no) n
WHERE c.vendor_no = n.vendor_no AND c.is_current;

INSERT INTO core.dim_vendor (vendor_no, vendor_name, attr_hash, first_seen_on, valid_from, valid_to, is_current, batch_id)
SELECT n.vendor_no, n.vendor_name, n.attr_hash, n.seen_from,
       CASE WHEN NOT EXISTS (SELECT 1 FROM core.dim_vendor c WHERE c.vendor_no = n.vendor_no)
                 AND n.rn = 1 THEN DATE '1900-01-01' ELSE n.seen_from END,
       coalesce(lead(n.seen_from) OVER w - 1, DATE '9999-12-31'),
       lead(n.seen_from) OVER w IS NULL,
       current_setting('pipeline.batch_id')::bigint
FROM _vendor_new n
WINDOW w AS (PARTITION BY n.vendor_no ORDER BY n.seen_from);
