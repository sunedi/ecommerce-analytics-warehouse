# Executive summary

Analysis of 96,478 delivered orders from 93,358 customers on the Olist marketplace. Monthly figures cover the complete months January 2017 to August 2018. Every number below comes from a query in [`queries/`](../queries); definitions are in [`docs/assumptions.md`](../docs/assumptions.md). Amounts are in Brazilian reais (R$).

## Key findings

1. **Growth came from more orders, not bigger ones.** Revenue for January–August grew 141% from 2017 to 2018. The number of orders grew 140%, while the average order value moved only 0.5% (R$136).
2. **Late delivery is the strongest warning sign for a bad review.** Orders delivered 8+ days late average 1.7 stars, and 70% of them get 1 star. Orders delivered more than a week early average 4.3 stars.
3. **Almost no one comes back.** Only 2.0% of customers placed another order within 180 days. 30% of "repeat" customers' second orders were placed the same day as the first, so they were split baskets rather than returning customers.
4. **Office furniture disappoints even when it arrives on time.** Its on-time orders score 3.77, which is 0.53 below the average for on-time orders. Bed, bath and table, the third-largest category, is also below average.
5. **R$162,592 was paid on 775 orders that have no items**, mostly orders marked unavailable or cancelled. The dataset has no refund records, so it can't confirm the money was returned.

## 1. What drives monthly revenue? ([`01_monthly_revenue.sql`](../queries/01_monthly_revenue.sql))

| | Jan–Aug 2017 | Jan–Aug 2018 | Change |
|---|---:|---:|---:|
| Delivered orders | 21,998 | 52,783 | +139.9% |
| Average order value | R$136.08 | R$136.75 | +0.5% |
| Revenue | | | +141.1% |

- **Revenue climbed through 2017, then levelled off in 2018** at R$0.83–0.98M a month.
- **Black Friday (24 November 2017) was the biggest day in the data:** 1,147 orders and R$149,917, 4.6 times an average November day. November 2017 revenue was 52% above October.
- **Freight was 13.8% of what customers paid in January–August 2017 and 14.6% in 2018.**
- **Location matters.** São Paulo state gives 38% of revenue, and São Paulo, Rio de Janeiro and Minas Gerais together give 63%. Customers in the north and northeast pay the most for delivery: freight is 21.8% of the bill in Roraima and 20.8% in Maranhão, against 12.2% in São Paulo. They also place larger orders (R$218 average in Paraíba against R$125 in São Paulo). This may be because freight makes small orders poor value at a distance. The data shows the pattern but not the reason.

## 2. How do repeat customers differ? ([`02_repeat_customers.sql`](../queries/02_repeat_customers.sql))

| | Customers | % of customers | % of revenue | Average order value | Revenue per customer |
|---|---:|---:|---:|---:|---:|
| One-time | 90,557 | 97.0% | 94.5% | R$137.96 | R$137.96 |
| Repeat (2+ delivered orders) | 2,801 | 3.0% | 5.5% | R$123.02 | R$260.05 |

- **Second orders are often not real returns.** 29.6% of repeat customers placed their second order on the same day as the first. 51% ordered again within 30 days.
- **The first order makes little measurable difference.** Of customers whose first order was between January 2017 and early March 2018 (all given a full 180 days to return), 1.99% came back. The 95% interval is 1.87–2.10%.

| First order | Came back within 180 days | 95% interval |
|---|---:|---:|
| Delivered on time | 2.01% | 1.89–2.13% |
| Delivered late | 1.60% | 1.21–2.00% |
| Rated 5 stars | 2.12% | 1.97–2.28% |
| Rated 1 star | 1.73% | 1.39–2.07% |

The direction is what you'd expect: a better first experience goes with a higher return rate. But the intervals overlap, so the data can't show that the first order's experience changes whether customers return.

## 3. Late deliveries and reviews ([`03_delivery_and_reviews.sql`](../queries/03_delivery_and_reviews.sql))

| Arrival against estimated date | Orders | Average score | 1-star | 5-star |
|---|---:|---:|---:|---:|
| 15+ days early | 34,771 | 4.32 | 6.5% | 64.3% |
| 8–14 days early | 36,158 | 4.31 | 6.4% | 63.0% |
| 1–7 days early | 17,234 | 4.20 | 7.1% | 57.5% |
| On the estimated day | 1,280 | 4.03 | 8.5% | 50.6% |
| 1–3 days late | 1,852 | 3.29 | 25.1% | 33.2% |
| 4–7 days late | 1,748 | 2.10 | 58.6% | 14.1% |
| 8+ days late | 2,781 | 1.70 | 69.8% | 7.0% |

- **6.8% of delivered orders arrived late overall, but with spikes:**
  - 12.4% in November 2017 (the Black Friday peak).
  - 14.1% in February 2018 and 19.0% in March 2018.
- **Deliveries got faster:** the median fell from about 10 days in 2017 to 7 days in August 2018. Olist also cut its promised delivery time from about 24 days to 16. So the late rate rose from 1.2% in June 2018 to 6.2% in August 2018, even though deliveries were quicker.
- **Lateness is spread across sellers.** Sellers with 50+ orders were split into ten equal groups by late rate:
  - The worst tenth is late on 15.5% of orders, against 0.9% for the best tenth.
  - But the worst tenth accounts for only 15.3% of all late orders, so most lateness is platform-wide.
- **Remote states wait longest.** Customers in the north and northeast wait 18–26 days on average, against 8.7 days in São Paulo. The highest late rates are in Alagoas (21.5%) and Maranhão (17.5%), and those states also give lower review scores.

## 4. Categories ([`04_categories.sql`](../queries/04_categories.sql))

- **A few categories dominate.** There are 74 categories, but the top 7 give half of revenue and the top 15 give 76%.
- **The leaders** are health and beauty (9.3% of revenue), watches and gifts (8.8%, highest average item price at R$199) and bed, bath and table (7.8%, the most orders).
- **Lower-scoring categories,** compared with all orders (average score 4.16, 9.7% 1-star, 6.8% late):

| Category | Revenue rank | Average score | 1-star | Late | Score when on time |
|---|---:|---:|---:|---:|---:|
| office_furniture | 15 | 3.65 | 17.0% | 8.1% | 3.77 |
| bed_bath_table | 3 | 4.00 | 12.0% | 7.4% | 4.14 |
| telephony | 14 | 4.05 | 10.4% | 7.1% | 4.18 |
| furniture_decor | 6 | 4.06 | 11.6% | 7.2% | 4.19 |
| computers_accessories | 5 | 4.08 | 11.3% | 6.4% | 4.20 |

These categories are late about as often as the average order. Their low scores remain even on on-time orders (average on-time score: 4.29), so delivery doesn't explain them.

## 5. Payment reconciliation ([`05_payment_reconciliation.sql`](../queries/05_payment_reconciliation.sql))

| Status | Orders | Difference (R$) |
|---|---:|---:|
| Matched within R$0.01 | 98,362 (98.9%) | -0.67 |
| Paid more than due | 264 | +3,070.14 |
| Paid less than due | 39 | -199.08 |
| Paid, but no items recorded | 775 | +162,591.95 |
| Items, but no payment recorded | 1 | -143.46 |

- **Paid but no items:** 603 orders marked unavailable (R$124,339) and 164 cancelled (R$37,338). Customers paid for orders that were never fulfilled.
- **Every exception is tracked** in an exception register (`audit.payment_exception`) with a reason code and severity, and the register is updated on every build. See [`docs/controls.md`](../docs/controls.md).
- **Overpayments rise with instalments,** which fits card interest being included in the payment value:

| Instalments | Overpaid orders | Overpaid by |
|---|---:|---:|
| Single payment | 0.03% | 0.1% of the amount due |
| 2–5 | 0.33% | 5.1% |
| 6–10 | 0.71% | 8.9% |
| 11+ | 7.12% | 17.8% |

## Recommendations

1. **Protect the delivery promise, especially at peaks.** Late orders are where 1-star reviews come from. Set estimated dates by region, and plan carrier capacity before November and the February–March period. Watch the shorter promises introduced in mid-2018: the late rate rose from 1.2% to 6.2% in two months.
2. **Treat retention as an open question, not a solved one.** The business grows by finding new customers, and only 2% return. Test retention offers, such as a follow-up voucher after delivery, with a control group. Don't assume that faster delivery alone will bring customers back; the data doesn't show that.
3. **Investigate office furniture and bed, bath and table.** Read their 1-star review comments for repeated product, description or assembly complaints. These categories score low even when delivery goes well.
4. **Set seller delivery targets, but fix logistics first.** The worst tenth of sellers is late 17 times as often as the best tenth (15.5% against 0.9%), so targets are worth having. But they would address only about 15% of late orders.
5. **Reconcile the R$162,592 paid on unfulfilled orders against refund records,** and chase the one delivered order with no payment (R$143.46). Confirm that instalment interest is accounted for separately from sales.

## Limitations

- **Data:** this is Olist's public, anonymised sample of about 100,000 orders. It has no product costs, margins, marketing spend or refunds, so profitability and acquisition cost can't be measured.
- **Reviews:** 99.2% of orders have a review score, but the score reflects the whole experience (delivery, seller and product), not only the product.
- **Correlation, not causation:** the links between delivery, reviews and returning describe patterns, not proven effects.
- **Excluded periods:** September 2016 – December 2016 and September–October 2018 are left out of monthly trends because they are incomplete.
