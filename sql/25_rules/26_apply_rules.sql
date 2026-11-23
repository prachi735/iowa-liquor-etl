-- Apply the rule tables in core.category_group_rule and core.store_type_rule.
-- Runs after every batch, and on its own with: python -m pipeline rules
-- (edit a rule, run that command, and the dimensions and marts follow).

-- Category group: the longest matching code prefix wins.
UPDATE core.dim_category c
SET category_group = m.category_group
FROM (
    SELECT d.category_code,
           coalesce((SELECT r.category_group
                     FROM core.category_group_rule r
                     WHERE d.category_code LIKE r.code_prefix || '%'
                     ORDER BY length(r.code_prefix) DESC
                     LIMIT 1), 'Unmapped') AS category_group
    FROM core.dim_category d
) m
WHERE c.category_code = m.category_code
  AND c.category_group IS DISTINCT FROM m.category_group;

-- Store chain and type: the lowest priority number whose pattern matches the name wins.
UPDATE core.dim_store d
SET chain = m.chain, store_type = m.store_type
FROM (
    SELECT s.store_sk,
           CASE WHEN r.store_type IS NULL THEN 'Independent' ELSE coalesce(r.chain, 'Independent') END AS chain,
           coalesce(r.store_type, 'Other') AS store_type
    FROM core.dim_store s
    LEFT JOIN LATERAL (
        SELECT r.chain, r.store_type
        FROM core.store_type_rule r
        WHERE s.store_name LIKE r.name_pattern
        ORDER BY r.priority
        LIMIT 1
    ) r ON true
) m
WHERE d.store_sk = m.store_sk
  AND (d.chain, d.store_type) IS DISTINCT FROM (m.chain, m.store_type);
