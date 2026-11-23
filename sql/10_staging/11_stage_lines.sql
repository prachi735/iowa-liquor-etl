-- Stage the current batch: type, clean and validate raw rows.
-- Rows that cannot be used go to staging.rejects with a reason; nothing is silently dropped.

TRUNCATE staging.liquor_sales;
DELETE FROM staging.rejects WHERE batch_id = current_setting('pipeline.batch_id')::bigint;

CREATE TEMP TABLE _typed ON COMMIT DROP AS
SELECT
    r.batch_id,
    r.row_no,
    staging.clean_text(r.invoice_id)                     AS invoice_id,
    staging.to_date(r.ordered_on)                        AS ordered_on,
    staging.clean_key(r.store_no)                        AS store_no,
    staging.clean_text(r.store_name)                     AS store_name,
    staging.clean_text(r.store_address)                  AS store_address,
    staging.clean_text(r.store_city)                     AS store_city,
    substring(r.store_zip_code FROM '^\s*(\d{5})')       AS store_zip,
    substring(r.county_fips_code FROM '^\s*(\d{5})')     AS county_fips,
    staging.clean_text(r.county_name)                    AS county_name,
    staging.clean_key(r.category_code)                   AS category_code,
    staging.clean_text(r.category_name)                  AS category_name,
    staging.clean_key(r.vendor_number)                   AS vendor_no,
    staging.clean_text(r.vendor_name)                    AS vendor_name,
    staging.clean_key(r.item_no)                         AS item_no,
    staging.clean_text(r.im_desc)                        AS item_desc_raw,
    round(staging.to_num(r.pack))::int                   AS pack,
    staging.to_num(r.bottle_volume_ml)                   AS bottle_volume_ml,
    staging.to_num(r.state_bottle_cost)                  AS list_cost,
    staging.to_num(r.state_bottle_retail)                AS list_retail,
    staging.to_num(r.sales_bottles)                      AS bottles,
    staging.to_num(r.sales_dollars)                      AS dollars,
    staging.to_num(r.sales_liters)                       AS liters,
    staging.to_num(r.sales_gallons)                      AS gallons
FROM raw.liquor_sales r
WHERE r.batch_id = current_setting('pipeline.batch_id')::bigint;

ALTER TABLE _typed ADD COLUMN reject_reason text;

UPDATE _typed SET reject_reason = CASE
    WHEN invoice_id IS NULL                       THEN 'missing invoice_id'
    WHEN ordered_on IS NULL                       THEN 'invalid ordered_on'
    WHEN ordered_on > current_date                THEN 'ordered_on in the future'
    WHEN store_no IS NULL                         THEN 'missing store_no'
    WHEN item_no IS NULL                          THEN 'missing item_no'
    WHEN bottles IS NULL OR bottles <> trunc(bottles) THEN 'invalid sales_bottles'
    WHEN dollars IS NULL                          THEN 'invalid sales_dollars'
END;

INSERT INTO staging.rejects (batch_id, row_no, reason, raw_row)
SELECT t.batch_id, t.row_no, t.reject_reason, to_jsonb(r) - 'batch_id'
FROM _typed t
JOIN raw.liquor_sales r ON r.batch_id = t.batch_id AND r.row_no = t.row_no
WHERE t.reject_reason IS NOT NULL;

INSERT INTO staging.liquor_sales
SELECT
    s.*,
    -- Hashes use normalised values so a change in number formatting is not seen as a change.
    md5(ROW(s.invoice_id, s.item_no, s.line_seq, s.ordered_on, s.store_no, s.vendor_no, s.category_code,
            s.bottles, trim_scale(s.dollars), trim_scale(s.liters),
            trim_scale(s.list_retail), trim_scale(s.list_cost))::text)                    AS line_hash,
    md5(ROW(s.store_name, s.store_address, s.store_city, s.store_zip,
            s.county_fips, s.county_name)::text)                                          AS store_hash,
    md5(ROW(s.item_desc_raw, s.category_code, s.category_name, s.vendor_no,
            s.pack, trim_scale(s.bottle_volume_ml))::text)                                AS item_hash,
    md5(ROW(s.vendor_name)::text)                                                         AS vendor_hash
FROM (
    SELECT
        t.batch_id,
        t.row_no,
        t.invoice_id,
        -- No line number is published since the invoice format change, so lines of the same
        -- item on one invoice are numbered by quantity and value.
        row_number() OVER (PARTITION BY t.invoice_id, t.item_no
                           ORDER BY t.bottles, t.dollars, t.row_no)::int        AS line_seq,
        t.ordered_on,
        t.store_no, t.store_name, t.store_address, t.store_city, t.store_zip,
        t.county_fips, t.county_name,
        t.category_code, t.category_name,
        t.vendor_no, t.vendor_name,
        t.item_no,
        t.item_desc_raw,
        staging.item_desc(t.item_desc_raw)                                    AS item_desc,
        staging.product_line(staging.item_desc(t.item_desc_raw))              AS product_line,
        substring(t.item_desc_raw FROM 'USE CODE\s*(\d+)')                    AS replaced_by_item_no,
        t.pack,
        t.bottle_volume_ml,
        t.list_cost,
        t.list_retail,
        t.bottles::int,
        t.dollars,
        t.liters,
        t.gallons,
        -- The price actually charged. The list price column is empty before July 2025
        -- and, where present, disagrees with dollars on about 0.7% of lines.
        round(t.dollars / nullif(t.bottles, 0), 4)                            AS unit_price,
        (t.invoice_id LIKE 'RINV%' OR t.bottles < 0)                          AS is_return
    FROM _typed t
    WHERE t.reject_reason IS NULL
) s;

ANALYZE staging.liquor_sales;

UPDATE ops.batch b
SET window_start = w.first_day, window_end = w.last_day
FROM (SELECT min(ordered_on) AS first_day, max(ordered_on) AS last_day FROM staging.liquor_sales) w
WHERE b.batch_id = current_setting('pipeline.batch_id')::bigint;
