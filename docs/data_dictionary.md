# Data dictionary

Source columns are listed on the [dataset page](https://data.iowa.gov/catalog/dataset/1051) (23 columns). Below are the tables the pipeline builds.

## core

**fact_sales** — one row per order line.

| Column | Meaning |
| --- | --- |
| `invoice_id`, `line_seq` | Invoice and line number within the invoice for that item (with `item_no`, unique) |
| `ordered_on` | Order date |
| `store_no`, `item_no`, `vendor_no`, `category_code` | Natural keys as sent on the line, normalised |
| `store_sk`, `item_sk`, `vendor_sk` | The dimension version valid on `ordered_on` |
| `bottles`, `dollars`, `liters` | Quantities; negative on returns |
| `unit_price` | `dollars / bottles`: the price charged |
| `list_retail`, `list_cost` | State list price per bottle (empty before Jul 2025) |
| `is_return` | `RINV-` invoice or negative bottles |
| `line_hash`, `batch_id` | Change detection and the batch that wrote the line |

**invoice** — one row per invoice ever seen: `ordered_on`, `store_no`, `line_count`, `dollars`, `invoice_hash`, and `first_batch_id`, `last_batch_id`, `changed_batch_id`, `deleted_batch_id` for audit.

**dim_store**, **dim_item**, **dim_vendor** — type 2. Each version has `valid_from` / `valid_to` (the first version starts 1900-01-01), `first_seen_on` (the real first date), `is_current` and `attr_hash`.

| Table | Attributes |
| --- | --- |
| `dim_store` | name, address, city, zip, county FIPS and name; `chain` and `store_type` from `store_type_rule` |
| `dim_item` | raw and clean description, `product_line`, `replaced_by_item_no`, category, vendor, pack, bottle size, `size_band` |
| `dim_vendor` | vendor name |

**dim_category** — latest name per code and `category_group` from `category_group_rule`.

**category_group_rule**, **store_type_rule** — editable rule tables; dimensions re-apply them every run.

## marts (defined in setup with primary keys; refreshed via TRUNCATE + INSERT every run)

| Table | Grain | Answers |
| --- | --- | --- |
| `monthly_kpis` | month | Dollars, litres, bottles, invoices, stores, items, returns, dollars per litre |
| `category_month` | month × category group | Share of dollars and litres (Q1) |
| `price_tier_month` | month × category group × price tier | Spend by price per 750 ml equivalent (Q2) |
| `product_line_month` | month × product line | Stores ordering and litres per store (Q3) |
| `size_store_type_month` | month × size band × store type | Small-bottle growth by store type (Q4) |
| `item_lifecycle` | item | First and last month, still ordered after 12 months (Q5) |
| `store_year` | year × store | Dollars, share, rank and percentile (Q6) |

## ops

| Table | Holds |
| --- | --- |
| `run` | One row per command: start, finish, status, error message |
| `run_step` | Each unit of work with timing, rows and status |
| `batch` | File manifest: name, SHA-256, size, rows, order-date window, status |
| `check_result` | Every check result per run and batch |
