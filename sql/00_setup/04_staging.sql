-- Staging: cleaning functions, the typed copy of the batch being processed, and rejects.

-- Trim, collapse inner spaces, upper-case; blank becomes NULL.
CREATE OR REPLACE FUNCTION staging.clean_text(t text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE
RETURN nullif(upper(regexp_replace(btrim(t), '\s+', ' ', 'g')), '');

-- Codes and numbers used as keys: '010017', '10017' and '10017.0' all become '10017'.
CREATE OR REPLACE FUNCTION staging.clean_key(t text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE
RETURN CASE
    WHEN regexp_replace(btrim(t), '\.0+$', '') ~ '^[0-9]+$'
        THEN coalesce(nullif(ltrim(regexp_replace(btrim(t), '\.0+$', ''), '0'), ''), '0')
    ELSE staging.clean_text(t)
END;

-- Numbers that fail to parse become NULL instead of stopping the load.
CREATE OR REPLACE FUNCTION staging.to_num(t text) RETURNS numeric
LANGUAGE sql STABLE PARALLEL SAFE
RETURN CASE WHEN pg_input_is_valid(btrim(t), 'numeric') THEN btrim(t)::numeric END;

-- Dates as YYYY-MM-DD (current format, a time part is ignored) or MM/DD/YYYY (older exports).
CREATE OR REPLACE FUNCTION staging.to_date(t text) RETURNS date
LANGUAGE sql STABLE PARALLEL SAFE
RETURN CASE
    WHEN btrim(t) ~ '^\d{4}-\d{2}-\d{2}' AND pg_input_is_valid(left(btrim(t), 10), 'date')
        THEN left(btrim(t), 10)::date
    WHEN btrim(t) ~ '^\d{1,2}/\d{1,2}/\d{4}$'
         AND pg_input_is_valid(regexp_replace(btrim(t), '^(\d+)/(\d+)/(\d{4})$', '\3-\1-\2'), 'date')
        THEN regexp_replace(btrim(t), '^(\d+)/(\d+)/(\d{4})$', '\3-\1-\2')::date
END;

-- Item description without the "USE CODE nnnnn" replacement note.
CREATE OR REPLACE FUNCTION staging.item_desc(raw_desc text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE
RETURN nullif(btrim(regexp_replace(raw_desc, '\s*-?\s*USE CODE\s*\d+\s*$', '')), '');

-- Product line: one name for all sizes and formats of a product, so TITOS HANDMADE VODKA,
-- TITOS HANDMADE VODKA MINI and TITOS HANDMADE VODKA MINI 4 PACK group together.
-- Strips status prefixes (SOOH, HA, BP), value-add text after W/, pack counts,
-- and trailing format words (MINI, PET, FLASK, SLEEVE, CARRIER, VAP, 100ML, GIFT SET...).
CREATE OR REPLACE FUNCTION staging.product_line(item_desc text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE
RETURN nullif(btrim(
    regexp_replace(regexp_replace(regexp_replace(regexp_replace(
        item_desc,
        '^(SOOH|HA|BP)\s+', ''),
        '\s+W/.*$', ''),
        '\s+\d+\s*(-\s*\d+\s*)?(PK|PACK)\M.*$', ''),
        '(\s+(MINIS?|PET|FLASK|SLEEVE|CARRIER|VAP|\d+\s?MLS?|GIFT (SET|BOX|PACKS?)))+$', '')
), '');

CREATE TABLE IF NOT EXISTS staging.liquor_sales (
    batch_id            bigint  NOT NULL,
    row_no              bigint  NOT NULL,
    invoice_id          text    NOT NULL,
    line_seq            int     NOT NULL,   -- 1, 2... when an invoice lists the same item twice
    ordered_on          date    NOT NULL,
    store_no            text    NOT NULL,
    store_name          text,
    store_address       text,
    store_city          text,
    store_zip           text,
    county_fips         text,
    county_name         text,
    category_code       text,
    category_name       text,
    vendor_no           text,
    vendor_name         text,
    item_no             text    NOT NULL,
    item_desc_raw       text,
    item_desc           text,
    product_line        text,
    replaced_by_item_no text,
    pack                int,
    bottle_volume_ml    numeric(8, 1),
    list_cost           numeric(12, 2),
    list_retail         numeric(12, 2),
    bottles             int     NOT NULL,
    dollars             numeric(14, 2) NOT NULL,
    liters              numeric(14, 3),
    gallons             numeric(14, 6),
    unit_price          numeric(12, 4),
    is_return           boolean NOT NULL,
    line_hash           text    NOT NULL,
    store_hash          text    NOT NULL,
    item_hash           text    NOT NULL,
    vendor_hash         text    NOT NULL
);

CREATE TABLE IF NOT EXISTS staging.rejects (
    batch_id    bigint      NOT NULL,
    row_no      bigint      NOT NULL,
    reason      text        NOT NULL,
    raw_row     jsonb       NOT NULL,
    rejected_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (batch_id, row_no)
);
