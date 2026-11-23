-- A few rejects are tolerated; more than 0.1% of the file means something upstream broke.
SELECT 'rejected rows' AS check_name,
       CASE WHEN j.n > greatest(10, 0.001 * r.n) THEN 'error' ELSE 'warning' END AS severity,
       j.n AS failed_rows,
       format('%s of %s rows rejected%s', j.n, r.n,
              coalesce(' (' || (SELECT string_agg(reason || ': ' || n, ', ' ORDER BY n DESC)
                                FROM (SELECT reason, count(*) AS n FROM staging.rejects
                                      WHERE batch_id = current_setting('pipeline.batch_id')::bigint
                                      GROUP BY reason) x) || ')', '')) AS detail
FROM (SELECT count(*) AS n FROM raw.liquor_sales
      WHERE batch_id = current_setting('pipeline.batch_id')::bigint) r,
     (SELECT count(*) AS n FROM staging.rejects
      WHERE batch_id = current_setting('pipeline.batch_id')::bigint) j;
