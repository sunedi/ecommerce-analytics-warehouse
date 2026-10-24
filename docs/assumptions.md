# Assumptions and decisions

How each data issue found in [`data_profile.md`](data_profile.md) is handled. The raw and staging layers keep the data exactly as received. These decisions are applied in the warehouse (`dw`) layer and the analysis queries, so each one can be changed in a single place.

## Business definitions

**1. The order date is the purchase timestamp.**
`order_approved_at` is missing for 160 orders and comes after the carrier hand-off for 1,359, so it is not a reliable event to date revenue by. Olist doesn't provide a payment-completion history.

**2. Revenue counts delivered orders only.**
- Revenue is the sum of item prices on orders with status `delivered`: R$13.22M of the R$13.59M listed across all orders (97.3%).
- Freight is reported separately, never added to revenue.
- Orders that are shipped, invoiced, processing or approved but never delivered may still be cancelled. Canceled and unavailable orders never completed.
- The value of non-delivered orders is reported separately, so the effect of this choice is visible.

**3. Monthly trends use January 2017 to August 2018.**
The months before and after this range hold 349 orders between them, against more than 6,000 in a typical month. They are kept in the warehouse but left out of month-by-month comparisons so that partial months don't look like collapses.

**4. A customer is a `customer_unique_id`.**
`customer_id` is created fresh for every order, so it can't identify repeat customers. Every customer count and repeat-purchase metric uses `customer_unique_id`.

**5. Customer location is tracked over time (slowly changing dimension, Type 2).**
- 250 repeat customers ordered from different ZIP prefixes (39 from different states).
- `dim_customer` keeps one row per customer per location, with the dates each location was valid.
- Orders link to the row valid at purchase time, so regional analysis uses where the customer actually was.

## Data quality handling

**6. Reviews.**
- Reviews are stored at the grain `review_id + order_id`, the only unique key. A review shared by several orders (789 cases) applies to each of them.
- When an order has several reviews (547 orders, 202 with different scores), the order's score is that of the **most recently answered** review. There are no ties.
- Review counts use distinct `review_id`.

**7. Orders without items** (775, almost all `unavailable` or `canceled`) stay in `fct_order` with zero item measures. They count in order-status analysis but add nothing to revenue.

**8. Products without a category** (610) are labelled `unknown`. Two categories missing from the translation table get English names in the warehouse:
- `pc_gamer` becomes `pc_gamer`.
- `portateis_cozinha_e_preparadores_de_alimentos` becomes `portable_kitchen_and_food_preparers`.

**9. One location per ZIP prefix.**
- Geolocation is reduced to one row per prefix: the average latitude and longitude of the points inside Brazil, and the most common state.
- 5 prefixes with no point inside Brazil, and the 278 customers and 7 sellers whose prefixes are missing from geolocation, get no coordinates. Their state is still known from the customer or seller record.
- City names are not used for analysis because spellings are inconsistent. State is clean and validated.

**10. Delivery times use purchase → delivered to customer only.**
- That interval has no out-of-order timestamps.
- Carrier and approval timestamps are not used for timing. They break the expected order in 1,382 orders; some of those break more than one rule.
- Orders without a delivered date are excluded from delivery-time metrics, including the 8 `delivered` orders that have no date.

**11. Payment and item totals are not forced to agree.**
- 303 orders differ by more than R$0.01. Most overpayments are instalment orders, which suggests card interest.
- One delivered order has no payment.
- Revenue is based on item prices. The differences are reported as reconciliation exceptions in step 5, not hidden.

**12. Unusual but valid values are kept:** free freight (383 items), zero-value payments (9, including the 3 `not_defined`), zero instalments (2), products weighing 0 g (4), shipping limits after 2018 (4), reviews created before purchase (64). None of these changes revenue, and none can be corrected from the source.

**13. Contradictory statuses are kept as recorded:** 6 `canceled` orders have a delivered date. They count as canceled (status wins), so they are excluded from revenue.
