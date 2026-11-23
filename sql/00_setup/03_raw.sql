-- Raw layer: every column as text, exactly as delivered. Never updated.

-- COPY target for one file at a time; row_no keeps the file's row order.
CREATE UNLOGGED TABLE IF NOT EXISTS raw.liquor_sales_landing (
    row_no              bigint GENERATED ALWAYS AS IDENTITY,
    invoice_id          text, ordered_on       text, store_no         text, store_name     text,
    store_address       text, store_city       text, store_zip_code   text, county_fips_code text,
    county_name         text, category_code    text, category_name    text, vendor_number  text,
    vendor_name         text, item_no          text, im_desc          text, pack           text,
    bottle_volume_ml    text, state_bottle_cost text, state_bottle_retail text,
    sales_bottles       text, sales_dollars    text, sales_liters     text, sales_gallons  text
);

CREATE TABLE IF NOT EXISTS raw.liquor_sales (
    batch_id            bigint NOT NULL REFERENCES ops.batch,
    row_no              bigint NOT NULL,
    invoice_id          text, ordered_on       text, store_no         text, store_name     text,
    store_address       text, store_city       text, store_zip_code   text, county_fips_code text,
    county_name         text, category_code    text, category_name    text, vendor_number  text,
    vendor_name         text, item_no          text, im_desc          text, pack           text,
    bottle_volume_ml    text, state_bottle_cost text, state_bottle_retail text,
    sales_bottles       text, sales_dollars    text, sales_liters     text, sales_gallons  text,
    PRIMARY KEY (batch_id, row_no)
);
