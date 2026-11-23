-- Store dimension, type 2: a new version when name, address, city, zip or county changes.
-- Loads may overlap (each month can re-send earlier days), so only versions that start after
-- the current version's first date are added; re-running the same file adds nothing.

-- 1. One observation per store per order day (the last row of the day wins).
CREATE TEMP TABLE _store_obs ON COMMIT DROP AS
SELECT DISTINCT ON (store_no, ordered_on)
    store_no, ordered_on, store_name, store_address, store_city, store_zip, county_fips, county_name,
    store_hash AS attr_hash
FROM staging.liquor_sales
ORDER BY store_no, ordered_on, row_no DESC;

-- 2. Collapse consecutive days with the same attributes into versions ("islands").
CREATE TEMP TABLE _store_ver ON COMMIT DROP AS
SELECT DISTINCT ON (store_no, island)
    store_no, ordered_on AS seen_from, store_name, store_address, store_city, store_zip,
    county_fips, county_name, attr_hash
FROM (
    SELECT o.*, sum(changed) OVER (PARTITION BY store_no ORDER BY ordered_on) AS island
    FROM (SELECT o.*, (attr_hash IS DISTINCT FROM lag(attr_hash) OVER (PARTITION BY store_no ORDER BY ordered_on))::int AS changed
          FROM _store_obs o) o
) x
ORDER BY store_no, island, ordered_on;

-- 3. Keep versions newer than what core holds; drop a first one identical to the current version.
CREATE TEMP TABLE _store_new ON COMMIT DROP AS
SELECT v.*, row_number() OVER (PARTITION BY v.store_no ORDER BY v.seen_from) AS rn
FROM _store_ver v
LEFT JOIN core.dim_store c ON c.store_no = v.store_no AND c.is_current
WHERE c.store_sk IS NULL OR v.seen_from > c.first_seen_on;

DELETE FROM _store_new n
USING core.dim_store c
WHERE n.rn = 1 AND c.store_no = n.store_no AND c.is_current AND c.attr_hash = n.attr_hash;

-- 4. Close the current version of stores that changed.
UPDATE core.dim_store c
SET valid_to = n.first_from - 1, is_current = false
FROM (SELECT store_no, min(seen_from) AS first_from FROM _store_new GROUP BY store_no) n
WHERE c.store_no = n.store_no AND c.is_current;

-- 5. Insert the new versions; a store's very first version starts on 1900-01-01.
INSERT INTO core.dim_store (store_no, store_name, store_address, store_city, store_zip, county_fips,
                            county_name, attr_hash, first_seen_on, valid_from, valid_to, is_current, batch_id)
SELECT n.store_no, n.store_name, n.store_address, n.store_city, n.store_zip, n.county_fips,
       n.county_name, n.attr_hash, n.seen_from,
       CASE WHEN NOT EXISTS (SELECT 1 FROM core.dim_store c WHERE c.store_no = n.store_no)
                 AND n.rn = 1 THEN DATE '1900-01-01' ELSE n.seen_from END,
       coalesce(lead(n.seen_from) OVER w - 1, DATE '9999-12-31'),
       lead(n.seen_from) OVER w IS NULL,
       current_setting('pipeline.batch_id')::bigint
FROM _store_new n
WINDOW w AS (PARTITION BY n.store_no ORDER BY n.seen_from);
