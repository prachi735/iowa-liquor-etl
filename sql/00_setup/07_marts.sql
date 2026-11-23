-- Mart tables: defined once with primary keys so TRUNCATE + INSERT refreshes never break
-- downstream views, permissions or BI tools.

CREATE TABLE IF NOT EXISTS marts.monthly_kpis (
    month             date           PRIMARY KEY,
    dollars           numeric(16, 2) NOT NULL,
    liters            numeric(16, 3),
    bottles           bigint         NOT NULL,
    invoices          bigint         NOT NULL,
    stores_ordering   bigint         NOT NULL,
    items_ordered     bigint         NOT NULL,
    return_dollars    numeric(16, 2) NOT NULL,
    dollars_per_liter numeric(14, 2),
    order_days        bigint         NOT NULL
);
COMMENT ON TABLE marts.monthly_kpis IS 'Dollars, litres, orders and stores per month, net of returns';

CREATE TABLE IF NOT EXISTS marts.category_month (
    month          date           NOT NULL,
    category_group text           NOT NULL,
    dollars        numeric(16, 2) NOT NULL,
    liters         numeric(16, 3),
    bottles        bigint         NOT NULL,
    dollar_share   numeric(8, 4),
    liter_share    numeric(8, 4),
    PRIMARY KEY (month, category_group)
);
COMMENT ON TABLE marts.category_month IS 'Category group dollars, litres and share of the month';

CREATE TABLE IF NOT EXISTS marts.price_tier_month (
    month          date           NOT NULL,
    category_group text           NOT NULL,
    price_tier     text           NOT NULL,
    dollars        numeric(16, 2) NOT NULL,
    liters         numeric(16, 3),
    bottles        bigint         NOT NULL,
    PRIMARY KEY (month, category_group, price_tier)
);
COMMENT ON TABLE marts.price_tier_month IS 'Dollars and litres by price tier (per 750 ml equivalent) and category group';

CREATE TABLE IF NOT EXISTS marts.product_line_month (
    month            date           NOT NULL,
    product_line     text           NOT NULL,
    category_group   text           NOT NULL,
    stores_ordering  bigint         NOT NULL,
    liters           numeric(16, 3),
    dollars          numeric(16, 2) NOT NULL,
    liters_per_store numeric(14, 3),
    PRIMARY KEY (month, product_line, category_group)
);
COMMENT ON TABLE marts.product_line_month IS 'Product line distribution (stores ordering) and velocity (litres per store) by month';

CREATE TABLE IF NOT EXISTS marts.size_store_type_month (
    month      date           NOT NULL,
    size_band  text           NOT NULL,
    store_type text           NOT NULL,
    bottles    bigint         NOT NULL,
    liters     numeric(16, 3),
    dollars    numeric(16, 2) NOT NULL,
    PRIMARY KEY (month, size_band, store_type)
);
COMMENT ON TABLE marts.size_store_type_month IS 'Bottles, litres and dollars by bottle size band and store type';

CREATE TABLE IF NOT EXISTS marts.item_lifecycle (
    item_no                 text           PRIMARY KEY,
    item_desc               text,
    product_line            text,
    size_band               text,
    category_group          text           NOT NULL,
    first_month             date           NOT NULL,
    last_month              date           NOT NULL,
    months_with_orders      bigint         NOT NULL,
    is_launch               boolean        NOT NULL,
    has_12_months_history   boolean        NOT NULL,
    ordered_after_12_months boolean        NOT NULL,
    liters_first_12_months  numeric(16, 3),
    dollars_first_12_months numeric(16, 2)
);
COMMENT ON TABLE marts.item_lifecycle IS 'First and last order month per item, and whether it was still ordered after 12 months';

CREATE TABLE IF NOT EXISTS marts.store_year (
    year              int            NOT NULL,
    store_no          text           NOT NULL,
    store_name        text,
    store_city        text,
    chain             text,
    store_type        text,
    dollars           numeric(16, 2) NOT NULL,
    liters            numeric(16, 3),
    invoices          bigint         NOT NULL,
    dollar_share      numeric(10, 6),
    dollar_rank       bigint         NOT NULL,
    dollar_percentile numeric(6, 4),
    PRIMARY KEY (year, store_no)
);
COMMENT ON TABLE marts.store_year IS 'Store dollars per year with share, rank and percentile; current store name and type';
