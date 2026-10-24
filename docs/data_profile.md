# Data profile

Findings from profiling the staging tables. Every number comes from a query in [`profiling/`](../profiling), run against the dataset version recorded in [`data/source_manifest.csv`](../data/source_manifest.csv). How each finding is handled is set out in [`assumptions.md`](assumptions.md).

## Summary

| Area | Finding | Impact |
|---|---|---|
| Customers | 99,441 `customer_id`s belong to only 96,096 people (`customer_unique_id`) | Counting customers by `customer_id` hides every repeat buyer |
| Customers | 96.9% of customers ordered once; 2,997 ordered more than once | Repeat-purchase analysis works on a small group |
| Customers | 250 repeat customers ordered from different ZIP prefixes, 39 from different states | Customer location changes over time |
| Reviews | 789 `review_id`s are attached to more than one order; 547 orders have more than one review | Review counts and average scores depend on the grain chosen |
| Orders | 775 orders have no items, almost all `unavailable` or `canceled` | Item-based revenue excludes them automatically |
| Orders | Purchases run from Sep 2016 to Oct 2018, but Sep–Dec 2016 and Sep–Oct 2018 have very few orders | Monthly trends should use Jan 2017 – Aug 2018 |
| Timestamps | 1,359 orders were handed to the carrier before being approved; 166 before purchase | Approval and carrier timestamps are unreliable for timing |
| Payments | 98,362 of 98,665 orders' payments match items + freight within R$0.01 | Payments and item revenue mostly reconcile; 303 exceptions |
| Geolocation | About 53 rows per ZIP prefix, with different city spellings and 47 points outside Brazil | Must be reduced to one clean row per prefix before joining |
| Products | 610 products have no category; 2 categories have no English translation | Category analysis needs an "unknown" bucket and two manual translations |

## 1. Missing values

Source: [`01_column_profile.sql`](../profiling/01_column_profile.sql). All other columns are complete.

| Table | Column | Missing | % |
|---|---|---:|---:|
| order_reviews | review_comment_title | 87,658 | 88.34 |
| order_reviews | review_comment_message | 58,274 | 58.73 |
| orders | order_delivered_customer_date | 2,965 | 2.98 |
| products | product_category_name, product_name_length, product_description_length, product_photos_qty | 610 | 1.85 |
| orders | order_delivered_carrier_date | 1,783 | 1.79 |
| orders | order_approved_at | 160 | 0.16 |
| products | product_weight_g, product_length_cm, product_height_cm, product_width_cm | 2 | 0.01 |

The same 610 products are missing all four descriptive columns, so this is one gap, not four. Review comments are optional in the source system, so missing comments are expected.

## 2. Keys and duplicates

Source: [`02_keys_and_duplicates.sql`](../profiling/02_keys_and_duplicates.sql)

| Table | Key | Rows | Distinct keys | Duplicates |
|---|---|---:|---:|---:|
| orders | order_id | 99,441 | 99,441 | 0 |
| customers | customer_id | 99,441 | 99,441 | 0 |
| customers | customer_unique_id | 99,441 | 96,096 | 3,345 |
| products | product_id | 32,951 | 32,951 | 0 |
| sellers | seller_id | 3,095 | 3,095 | 0 |
| category_translation | product_category_name | 71 | 71 | 0 |
| order_items | order_id + order_item_id | 112,650 | 112,650 | 0 |
| order_payments | order_id + payment_sequential | 103,886 | 103,886 | 0 |
| order_reviews | review_id | 99,224 | 98,410 | 814 |
| order_reviews | order_id | 99,224 | 98,673 | 551 |
| order_reviews | review_id + order_id | 99,224 | 99,224 | 0 |
| geolocation | geolocation_zip_code_prefix | 1,000,163 | 19,015 | 981,148 |

- `order_item_id` numbers each order's items 1, 2, 3… with no gaps in all 98,666 orders that have items.
- **Shared reviews:** 789 `review_id`s appear on 2 or more orders (1,603 rows). Every copy has the same score and comment, so one review was recorded against several orders.
- **Several reviews per order:** 547 orders have 2 or more reviews (1,098 rows), and 202 of them have different scores. Picking the latest review is never ambiguous: no order has two reviews answered at the same moment.
- The only unique key for reviews is `review_id + order_id`.

## 3. Relationships

Source: [`03_relationships.sql`](../profiling/03_relationships.sql)

**Orphans.** There are none between the transaction tables: every order item, payment and review belongs to a real order, and every order item points to a real product and seller.

| Relationship | Rows checked | Orphans |
|---|---:|---:|
| products → category_translation | 32,341 with a category | 13 (categories `pc_gamer` and `portateis_cozinha_e_preparadores_de_alimentos`) |
| customers → geolocation (ZIP prefix) | 99,441 | 278 |
| sellers → geolocation (ZIP prefix) | 3,095 | 7 |

**Orders missing child rows:**

| Status | Orders | No items | No payment | No review |
|---|---:|---:|---:|---:|
| delivered | 96,478 | 0 | 1 | 646 |
| shipped | 1,107 | 1 | 0 | 75 |
| canceled | 625 | 164 | 0 | 20 |
| unavailable | 609 | 603 | 0 | 14 |
| invoiced | 314 | 2 | 0 | 5 |
| processing | 301 | 0 | 0 | 6 |
| created | 5 | 5 | 0 | 2 |
| approved | 2 | 0 | 0 | 0 |

One delivered order (`bfbd0f9bdef84302105ad712db648a6c`, R$143.46) has no payment record.

**Payments compared with items plus freight** (98,665 orders that have both). Totals are summed to one row per order before joining:

| Result | Orders | Total difference (R$) |
|---|---:|---:|
| Match within R$0.01 | 98,362 | -0.67 |
| Paid more | 264 | 3,070.14 |
| Paid less | 39 | -199.08 |

249 of the 264 overpaid orders were paid in instalments, which suggests card interest is included in the payment value.

## 4. Order lifecycle

Source: [`04_order_lifecycle.sql`](../profiling/04_order_lifecycle.sql)

| Status | Orders | Approved date | Carrier date | Delivered date |
|---|---:|---:|---:|---:|
| delivered | 96,478 | 96,464 | 96,476 | 96,470 |
| shipped | 1,107 | 1,107 | 1,107 | 0 |
| canceled | 625 | 484 | 75 | 6 |
| unavailable | 609 | 609 | 0 | 0 |
| invoiced | 314 | 314 | 0 | 0 |
| processing | 301 | 301 | 0 | 0 |
| created | 5 | 0 | 0 | 0 |
| approved | 2 | 2 | 0 | 0 |

**Timestamps out of order:**

| Rule broken | Orders |
|---|---:|
| Approved before purchase | 0 |
| Handed to carrier before purchase | 166 |
| Handed to carrier before approval | 1,359 |
| Delivered before purchase | 0 |
| Delivered before handed to carrier | 23 |
| Estimated delivery before purchase | 0 |
| Any of the above (distinct orders) | 1,382 |

**Status contradictions:** 8 orders are `delivered` but have no delivered date; 6 orders are `canceled` but have a delivered date.

**Monthly coverage:** the data runs from 4 Sep 2016 to 17 Oct 2018.
- Sep–Dec 2016 has only 329 orders, with none in November.
- Sep–Oct 2018 has only 20 orders, against more than 6,000 in each month before.
- Jan 2017 to Aug 2018 (20 months) is complete.

## 5. Values and ranges

Source: [`05_values_and_ranges.sql`](../profiling/05_values_and_ranges.sql)

| Finding | Rows |
|---|---:|
| Order items with price 0 or less | 0 |
| Order items with free freight | 383 |
| Payments of 0.00 | 9 |
| Payments with 0 instalments | 2 |
| Payments with type `not_defined` (all 0.00) | 3 |
| Products weighing 0 g | 4 |
| Order items with a shipping limit after 2018 | 4 |
| Reviews answered before they were created | 0 |
| Reviews created before the order was purchased | 64 |
| Geolocation points outside Brazil | 47 (in 23 ZIP prefixes; 5 prefixes have no point inside Brazil) |

**Payments by type:**

| Type | Payments | Orders | Value (R$) |
|---|---:|---:|---:|
| credit_card | 76,795 | 76,505 | 12,542,084.19 |
| boleto | 19,784 | 19,784 | 2,869,361.27 |
| voucher | 5,775 | 3,866 | 379,436.87 |
| debit_card | 1,529 | 1,528 | 217,989.79 |
| not_defined | 3 | 3 | 0.00 |

**Review scores:** 57.8% are 5 stars and 11.5% are 1 star. Scores in between are less common (2 stars: 3.2%), the U shape typical of review data.

**Prices:** the median item price is R$74.99 and the 99th percentile is R$890. The median freight is R$16.26.

## 6. Customers and locations

Source: [`06_customers_and_locations.sql`](../profiling/06_customers_and_locations.sql)

| Orders placed | Customers | % |
|---|---:|---:|
| 1 | 93,099 | 96.88 |
| 2 | 2,745 | 2.86 |
| 3 | 203 | 0.21 |
| 4 or more | 49 | 0.05 |

- Of the 2,997 customers with more than one order, 250 used more than one ZIP prefix and 39 more than one state.
- **Geolocation** covers 19,015 ZIP prefixes. Each prefix has 52.6 rows on average (the most is 1,146).
  - 8 prefixes appear in more than one state.
  - 8,555 prefixes have more than one city spelling, for example `sao paulo` and `são paulo` for prefix 01001.
  - City names elsewhere are messy too: one seller's city is the number `04482255`.
