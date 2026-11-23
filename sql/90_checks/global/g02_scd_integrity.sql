-- History tables: exactly one current version per key, and versions that neither overlap
-- nor leave gaps.
WITH versions AS (
    SELECT 'store' AS dim, store_no AS k, valid_from, valid_to, is_current FROM core.dim_store
    UNION ALL SELECT 'item', item_no, valid_from, valid_to, is_current FROM core.dim_item
    UNION ALL SELECT 'vendor', vendor_no, valid_from, valid_to, is_current FROM core.dim_vendor
), ordered AS (
    SELECT *, lead(valid_from) OVER (PARTITION BY dim, k ORDER BY valid_from) AS next_from
    FROM versions
), bad AS (
    SELECT dim, k FROM ordered WHERE next_from IS NOT NULL AND next_from <> valid_to + 1
    UNION
    SELECT dim, k FROM versions GROUP BY dim, k HAVING count(*) FILTER (WHERE is_current) <> 1
)
SELECT 'history tables consistent' AS check_name,
       'error' AS severity,
       count(*) AS failed_rows,
       coalesce('broken keys: ' || string_agg(dim || ' ' || k, ', '), 'one current version per key, no gaps')
       AS detail
FROM bad;
