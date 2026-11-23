-- Item dimension, type 2: a new version when description, category, vendor, pack or bottle size
-- changes. Price is not an attribute here: it changes monthly and lives on the fact.
-- Same steps as dim_store.

CREATE TEMP TABLE _item_obs ON COMMIT DROP AS
SELECT DISTINCT ON (item_no, ordered_on)
    item_no, ordered_on, item_desc_raw, item_desc, product_line, replaced_by_item_no,
    category_code, category_name, vendor_no, pack, bottle_volume_ml, item_hash AS attr_hash
FROM staging.liquor_sales
ORDER BY item_no, ordered_on, row_no DESC;

CREATE TEMP TABLE _item_ver ON COMMIT DROP AS
SELECT DISTINCT ON (item_no, island)
    item_no, ordered_on AS seen_from, item_desc_raw, item_desc, product_line, replaced_by_item_no,
    category_code, category_name, vendor_no, pack, bottle_volume_ml, attr_hash
FROM (
    SELECT o.*, sum(changed) OVER (PARTITION BY item_no ORDER BY ordered_on) AS island
    FROM (SELECT o.*, (attr_hash IS DISTINCT FROM lag(attr_hash) OVER (PARTITION BY item_no ORDER BY ordered_on))::int AS changed
          FROM _item_obs o) o
) x
ORDER BY item_no, island, ordered_on;

CREATE TEMP TABLE _item_new ON COMMIT DROP AS
SELECT v.*, row_number() OVER (PARTITION BY v.item_no ORDER BY v.seen_from) AS rn
FROM _item_ver v
LEFT JOIN core.dim_item c ON c.item_no = v.item_no AND c.is_current
WHERE c.item_sk IS NULL OR v.seen_from > c.first_seen_on;

DELETE FROM _item_new n
USING core.dim_item c
WHERE n.rn = 1 AND c.item_no = n.item_no AND c.is_current AND c.attr_hash = n.attr_hash;

UPDATE core.dim_item c
SET valid_to = n.first_from - 1, is_current = false
FROM (SELECT item_no, min(seen_from) AS first_from FROM _item_new GROUP BY item_no) n
WHERE c.item_no = n.item_no AND c.is_current;

INSERT INTO core.dim_item (item_no, item_desc_raw, item_desc, product_line, replaced_by_item_no,
                           category_code, category_name, vendor_no, pack, bottle_volume_ml, size_band,
                           attr_hash, first_seen_on, valid_from, valid_to, is_current, batch_id)
SELECT n.item_no, n.item_desc_raw, n.item_desc, n.product_line, n.replaced_by_item_no,
       n.category_code, n.category_name, n.vendor_no, n.pack, n.bottle_volume_ml,
       CASE WHEN n.bottle_volume_ml IS NULL  THEN 'Unknown'
            WHEN n.bottle_volume_ml <= 50    THEN '50 ml and under'
            WHEN n.bottle_volume_ml <= 200   THEN '100-200 ml'
            WHEN n.bottle_volume_ml <= 375   THEN '375 ml'
            WHEN n.bottle_volume_ml <= 1000  THEN '700 ml-1 L'
            ELSE '1.75 L and over' END,
       n.attr_hash, n.seen_from,
       CASE WHEN NOT EXISTS (SELECT 1 FROM core.dim_item c WHERE c.item_no = n.item_no)
                 AND n.rn = 1 THEN DATE '1900-01-01' ELSE n.seen_from END,
       coalesce(lead(n.seen_from) OVER w - 1, DATE '9999-12-31'),
       lead(n.seen_from) OVER w IS NULL,
       current_setting('pipeline.batch_id')::bigint
FROM _item_new n
WINDOW w AS (PARTITION BY n.item_no ORDER BY n.seen_from);
