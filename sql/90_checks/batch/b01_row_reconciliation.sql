-- Every raw row must end up either staged or rejected.
SELECT 'raw rows = staged + rejected' AS check_name,
       'error' AS severity,
       abs(r.n - s.n - j.n) AS failed_rows,
       format('raw %s, staged %s, rejected %s', r.n, s.n, j.n) AS detail
FROM (SELECT count(*) AS n FROM raw.liquor_sales
      WHERE batch_id = current_setting('pipeline.batch_id')::bigint) r,
     (SELECT count(*) AS n FROM staging.liquor_sales) s,
     (SELECT count(*) AS n FROM staging.rejects
      WHERE batch_id = current_setting('pipeline.batch_id')::bigint) j;
