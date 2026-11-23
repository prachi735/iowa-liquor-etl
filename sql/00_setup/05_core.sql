-- Core layer: dimensions keep a dated row per change (type 2); the fact holds order lines.
-- The first version of each key starts on 1900-01-01 so older facts always find a row;
-- first_seen_on keeps the real first date the version appeared in the data.

CREATE TABLE IF NOT EXISTS core.dim_store (
    store_sk      bigint  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    store_no      text    NOT NULL,
    store_name    text,
    store_address text,
    store_city    text,
    store_zip     text,
    county_fips   text,
    county_name   text,
    chain         text,      -- from core.store_type_rule
    store_type    text,      -- from core.store_type_rule
    attr_hash     text    NOT NULL,
    first_seen_on date    NOT NULL,
    valid_from    date    NOT NULL,
    valid_to      date    NOT NULL DEFAULT '9999-12-31',
    is_current    boolean NOT NULL DEFAULT true,
    batch_id      bigint  NOT NULL,
    UNIQUE (store_no, valid_from)
);
CREATE INDEX IF NOT EXISTS dim_store_lookup ON core.dim_store (store_no, valid_from, valid_to);

CREATE TABLE IF NOT EXISTS core.dim_item (
    item_sk             bigint  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_no             text    NOT NULL,
    item_desc_raw       text,
    item_desc           text,
    product_line        text,
    replaced_by_item_no text,  -- from "USE CODE nnnnn" in the description
    category_code       text,
    category_name       text,
    vendor_no           text,
    pack                int,
    bottle_volume_ml    numeric(8, 1),
    size_band           text,
    attr_hash           text    NOT NULL,
    first_seen_on       date    NOT NULL,
    valid_from          date    NOT NULL,
    valid_to            date    NOT NULL DEFAULT '9999-12-31',
    is_current          boolean NOT NULL DEFAULT true,
    batch_id            bigint  NOT NULL,
    UNIQUE (item_no, valid_from)
);
CREATE INDEX IF NOT EXISTS dim_item_lookup ON core.dim_item (item_no, valid_from, valid_to);

CREATE TABLE IF NOT EXISTS core.dim_vendor (
    vendor_sk     bigint  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vendor_no     text    NOT NULL,
    vendor_name   text,
    attr_hash     text    NOT NULL,
    first_seen_on date    NOT NULL,
    valid_from    date    NOT NULL,
    valid_to      date    NOT NULL DEFAULT '9999-12-31',
    is_current    boolean NOT NULL DEFAULT true,
    batch_id      bigint  NOT NULL,
    UNIQUE (vendor_no, valid_from)
);
CREATE INDEX IF NOT EXISTS dim_vendor_lookup ON core.dim_vendor (vendor_no, valid_from, valid_to);

-- Categories: latest name per code (type 1) plus the analysis group from core.category_group_rule.
CREATE TABLE IF NOT EXISTS core.dim_category (
    category_code  text PRIMARY KEY,
    category_name  text,
    category_group text,
    first_seen_on  date NOT NULL,
    last_seen_on   date NOT NULL
);

-- One row per invoice ever seen; the unit of change detection.
CREATE TABLE IF NOT EXISTS core.invoice (
    invoice_id       text    PRIMARY KEY,
    ordered_on       date    NOT NULL,
    store_no         text    NOT NULL,
    line_count       int     NOT NULL,
    dollars          numeric(14, 2) NOT NULL,
    is_return        boolean NOT NULL,
    invoice_hash     text    NOT NULL,
    first_batch_id   bigint  NOT NULL,
    last_batch_id    bigint  NOT NULL,   -- latest batch that contained it
    changed_batch_id bigint,             -- latest batch that changed its lines
    deleted_batch_id bigint              -- set when a later file covering its date no longer has it
);
CREATE INDEX IF NOT EXISTS invoice_ordered_on ON core.invoice (ordered_on);

CREATE TABLE IF NOT EXISTS core.fact_sales (
    sales_line_id bigint  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_id    text    NOT NULL REFERENCES core.invoice,
    line_seq      int     NOT NULL,
    ordered_on    date    NOT NULL,
    store_no      text    NOT NULL,
    item_no       text    NOT NULL,
    vendor_no     text,
    category_code text,
    store_sk      bigint  REFERENCES core.dim_store,
    item_sk       bigint  REFERENCES core.dim_item,
    vendor_sk     bigint  REFERENCES core.dim_vendor,
    bottles       int     NOT NULL,
    dollars       numeric(14, 2) NOT NULL,
    liters        numeric(14, 3),
    list_retail   numeric(12, 2),
    list_cost     numeric(12, 2),
    unit_price    numeric(12, 4),   -- dollars / bottles: the price actually charged
    is_return     boolean NOT NULL,
    line_hash     text    NOT NULL,
    batch_id      bigint  NOT NULL,
    UNIQUE (invoice_id, item_no, line_seq)
);
CREATE INDEX IF NOT EXISTS fact_sales_date  ON core.fact_sales (ordered_on);
CREATE INDEX IF NOT EXISTS fact_sales_store ON core.fact_sales (store_no, ordered_on);
CREATE INDEX IF NOT EXISTS fact_sales_item   ON core.fact_sales (item_no, ordered_on);
CREATE INDEX IF NOT EXISTS fact_sales_vendor ON core.fact_sales (vendor_no, ordered_on);
