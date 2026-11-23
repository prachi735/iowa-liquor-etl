# Business rules found in the data

Profiled on the past-30-days file: 225,299 order lines, 30 Sep to 30 Oct 2026, 12,096 invoices, 2,011 stores, 3,333 items. Numbers below come from that file unless a year is named.

| # | What the data does | Evidence | How the pipeline handles it |
| --- | --- | --- | --- |
| 1 | `invoice_id` names a whole invoice, not a line. The column notes say "invoice and line number", which held in 2012 (`S03399100016`) but not now (`INV-0996812`). | 12,096 ids for 225,299 lines; median 11 lines per invoice, max 657 | The invoice is the unit of change: new, changed, unchanged or deleted, compared by a hash of its lines. |
| 2 | No line number, and an item can appear twice on one invoice. | 315 invoice + item pairs appear twice; they differ only in quantity (for example 12 bottles and 1 bottle) | Lines get `line_seq` 1, 2... ordered by bottles and dollars. Both lines are kept. |
| 3 | Returns are separate invoices with negative quantities. | 219 lines on 191 `RINV-` invoices | Kept, flagged `is_return`; all marts are net of returns. |
| 4 | Store numbers come in two formats. | 4-digit (2130-9049) and zero-padded 6-digit (`010003`-`010903`); no clashes once zeros are stripped | Keys are normalised: leading zeros and a trailing `.0` removed (`010017` and `10017` match). Same for vendor and item numbers. |
| 5 | List prices are missing before 1 Jul 2025 (per the column notes) and, where present, disagree with dollars on some lines. | 1,599 lines (0.7%) differ from bottles × list price by more than a cent; for 1,161 of them, dollars ÷ bottles equals another list price the item had that month | `unit_price` = dollars ÷ bottles, the price actually charged. The list price is kept for reference and the mismatch is reported as a note. |
| 6 | Retail list price is the state's cost plus 50%. | Median retail ÷ cost = 1.500 | Documented only. |
| 7 | Store details change, and some are missing. | Store 4042 renamed from "LAKE OHANA MARKET / MINEOLA" to "/ GLENWOOD" on 9 Oct 2026; 140 lines from 2 stores have no address, city or county | `dim_store` keeps a dated version per change; blanks are kept as unknown, reported as a note. |
| 8 | Item descriptions carry status notes. | "DISARONNO AMARETTO USE CODE 64238" (item replaced by a new number); prefixes SOOH, HA and BP on some items | `replaced_by_item_no` is taken from "USE CODE"; `item_desc` drops the note; `product_line` also drops the prefixes. |
| 9 | Items move category, often for holiday packs. | Item 22340 moved from Straight Bourbon to Temporary & Specialty Packages on 1 Oct 2026; most item changes start on the 1st of a month | `dim_item` versions; the fact keeps the category code sent on each line. |
| 10 | One product comes in many sizes and formats. | TITOS HANDMADE VODKA has 8 item numbers, from a 50 ml mini (and a "MINI 4 PACK") to 1.75 L | `product_line` strips format words (MINI, PET, FLASK, 4 PACK, W/ gift text...): 3,333 items map to 2,354 product lines. |
| 11 | Category codes are a family scheme. | 1011xxx American whiskey, 1022xxx tequila, 1031/1032 vodka, 1701100 temporary packs; 44 codes in use | `core.category_group_rule` maps code prefixes to 15 groups; an unmapped code raises a warning. |
| 12 | Store type is only in the name. | Casey's has about 550 stores; "HY-VEE #3 / BDI / DES MOINES" ordered 2,688 bottles of Crown Royal ($70,533) on one line, a warehouse not a shop | `core.store_type_rule`: patterns map names to chain and type (grocery, convenience, liquor and tobacco, pharmacy, club and big box, warehouse). |
| 13 | Orders come Monday to Friday, with a trickle on Sundays. | 16-45 lines on each Sunday in the window | The weekday check flags missing weekdays (holidays or gaps). |
| 14 | Identical lines can sit on two invoices. | 578 groups of same store, date, item, bottles and dollars on different invoices | Counted as a note, never deleted: most are real repeat orders. |

Rules that stay open: the meaning of the SOOH, HA and BP prefixes is not documented; store types for independents come from name keywords and should be spot-checked; whether older years use the same category codes will show in the unmapped-category warning during the backfill.
