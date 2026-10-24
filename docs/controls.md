# Reconciliation controls

`audit.usp_run_controls` runs at the end of every build ([`sql/05_controls`](../sql/05_controls)) and records its results in three `audit` tables. The tests in [`tests/`](../tests) stop a build that is wrong; the controls keep a history of what was checked and what was found, run after run.

| Table | One row per |
|---|---|
| `audit.control_run` | Run: status, measures checked and failed, open, new and resolved exceptions |
| `audit.control_total` | Measure per layer per run |
| `audit.payment_exception` | Order that doesn't reconcile, with reason, severity and the runs that found it |

## Control totals

Each measure is taken from every layer it passes through. A run **passes** only if every layer gives the same value for every measure. A layer that returns nothing (an empty table) also fails it.

| Measure | Layers compared |
|---|---|
| Item count | Source file manifest → raw → stg → `fct_order_item` → `fct_order` |
| Order count | Source file manifest → raw → stg → `fct_order` → `mart.monthly_performance` → `mart.customer_summary` |
| Item price total | raw → stg → `fct_order_item` → `fct_order` |
| Freight total | raw → stg → `fct_order_item` → `fct_order` |
| Payment total | raw → stg → `fct_payment` → `fct_order` |
| Delivered revenue | `fct_order_item` → `fct_order` → all five marts with revenue |

Together they trace every order, item and centavo from the CSV file to the dashboard tables.

## Payment exceptions

An order is an exception when its payments don't match its item prices plus freight to within R$0.01:

| Reason code | Meaning | Orders (current data) | Amount (R$) |
|---|---|---:|---:|
| `PAID_NO_ITEMS` | Payments recorded, but no items: an unfulfilled order with no refund on record | 775 | 162,591.95 |
| `OVERPAID` | Paid more than items plus freight | 264 | 3,070.14 |
| `UNDERPAID` | Paid less than items plus freight | 39 | 199.08 |
| `NO_PAYMENT` | Items recorded, but no payment | 1 | 143.46 |

Severity is set by the absolute difference: **HIGH** at R$100 or more, **MEDIUM** at R$10 or more, **LOW** below that.

### Exception lifecycle

The register is updated with a single `MERGE`:

| Situation | What happens |
|---|---|
| Found for the first time | Inserted as `open`; `first_detected_run_id` = this run |
| Found again | Updated with current amounts; `last_detected_run_id` = this run |
| Open, but no longer found | Marked `resolved`; `resolved_run_id` = this run |
| Resolved, then found again | Reopened; keeps its original `first_detected_run_id` |

Rerunning the controls on unchanged data changes nothing: no duplicate rows, no new exceptions, nothing resolved.

## Evidence

These runs were made while building the controls:

| Run | Situation | Status | Open | New | Resolved |
|---:|---|---|---:|---:|---:|
| 1 | First run | passed | 1,079 | 1,079 | 0 |
| 2 | Full rebuild, same data | passed | 1,079 | 0 | 0 |
| 3 | One order's payment total altered in `fct_order` only | **failed** | 1,078 | 0 | 1 |
| 4 | Full rebuild from source | passed | 1,079 | 0 | 0 |

In run 3, the payment total measure showed R$16,008,872.12 in raw, stg and `fct_payment` but R$16,008,850.14 in `fct_order`. That pinpointed the layer where the R$21.98 went missing. The altered order's exception was resolved in run 3 and reopened in run 4 with `first_detected_run_id = 1`.

## Useful queries

```sql
-- Latest runs
SELECT TOP (10) * FROM audit.control_run ORDER BY run_id DESC;

-- Which layer disagrees, in the latest run
SELECT measure, layer, value
FROM audit.control_total
WHERE run_id = (SELECT MAX(run_id) FROM audit.control_run)
ORDER BY measure, layer;

-- Open exceptions to work through, largest first
SELECT reason_code, severity, order_id, order_status, amount_due, amount_paid, difference
FROM audit.payment_exception
WHERE status = 'open'
ORDER BY ABS(difference) DESC;
```

## Limitations

- The source has no refund records, so `PAID_NO_ITEMS` exceptions can't be closed by matching refunds. With refund data, refunded orders would be resolved automatically.
- When an exception reopens, its earlier resolution is overwritten. A separate history table would keep every status change if the full trail were needed.
