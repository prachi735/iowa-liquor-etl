-- A full month with less than half the dollars of the three months before it is
-- usually a missing file, not a real drop. The latest month may be partial and is skipped.
WITH m AS (
    SELECT date_trunc('month', ordered_on)::date AS month, sum(dollars) AS dollars
    FROM core.fact_sales GROUP BY 1
), cal AS (
    SELECT g::date AS month
    FROM generate_series((SELECT min(month) FROM m), (SELECT max(month) FROM m), interval '1 month') g
), t AS (
    SELECT cal.month, coalesce(m.dollars, 0) AS dollars,
           avg(coalesce(m.dollars, 0)) OVER (ORDER BY cal.month ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING) AS prior3,
           count(*) OVER (ORDER BY cal.month ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING) AS n_prior
    FROM cal LEFT JOIN m USING (month)
)
SELECT 'no missing months' AS check_name,
       'warning' AS severity,
       count(*) AS failed_rows,
       coalesce('low months: ' || string_agg(to_char(month, 'Mon YYYY'), ', ' ORDER BY month),
                'every month has normal volume') AS detail
FROM t
WHERE n_prior = 3 AND dollars < 0.5 * prior3
  AND month < (SELECT max(month) FROM m);
