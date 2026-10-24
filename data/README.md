# Source data

**Dataset:** [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (Kaggle, version 2, last updated 1 October 2021)

**Licence:** [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/). The raw files are not stored in this repository. Download them with the script below.

About 100,000 real, anonymised orders placed on the Olist marketplace in Brazil between 2016 and 2018.

## Getting the files

```
python scripts/get_data.py
```

This downloads the dataset from Kaggle, unpacks the nine CSV files into `data/raw/`, and checks each file's SHA-256 checksum against [`source_manifest.csv`](source_manifest.csv). If the automatic download does not work, download the zip from the Kaggle page yourself and run:

```
python scripts/get_data.py --zip path\to\brazilian-ecommerce.zip
```

A checksum mismatch means the files differ from the version this project was built and tested on.

## Files

The record counts come from `source_manifest.csv`. Grains are checked in the staging step.

| File | Raw table | Records | Contents |
|---|---|---:|---|
| `olist_orders_dataset.csv` | `raw.olist_orders` | 99,441 | Order status and timestamps from purchase to delivery |
| `olist_order_items_dataset.csv` | `raw.olist_order_items` | 112,650 | Products, sellers, prices and freight for each item in an order |
| `olist_order_payments_dataset.csv` | `raw.olist_order_payments` | 103,886 | Payment type, instalments and value (an order can have several payments) |
| `olist_order_reviews_dataset.csv` | `raw.olist_order_reviews` | 99,224 | Review scores and comments |
| `olist_customers_dataset.csv` | `raw.olist_customers` | 99,441 | Customer location. `customer_id` is per order; `customer_unique_id` identifies the person |
| `olist_products_dataset.csv` | `raw.olist_products` | 32,951 | Product category and physical attributes |
| `olist_sellers_dataset.csv` | `raw.olist_sellers` | 3,095 | Seller location |
| `olist_geolocation_dataset.csv` | `raw.olist_geolocation` | 1,000,163 | Latitude and longitude by ZIP code prefix (many rows per prefix) |
| `product_category_name_translation.csv` | `raw.product_category_name_translation` | 71 | Portuguese to English category names |

## Things to know about the files

These were found while building the raw load. The staging layer deals with them.

- **Review comments contain line breaks.** 3,852 reviews span several lines inside quotes, so the reviews file has 104,720 lines but only 99,224 records. Counting lines would give the wrong answer, so record counts use a CSV parser.
- **Line endings differ.** The reviews and category translation files use Windows line endings (CR LF); the other seven use LF only.
- **The translation file starts with a byte order mark.** It sits in the header row, which the load skips.
- **ZIP code prefixes have leading zeros** (e.g. `01037`), so they must stay as text.
- **Empty values.** For example, 2,965 orders have no delivery date and 610 products have no category. They load as NULL.
- **Some review comments are blank.** 27 contain only spaces or line breaks.
- **Emoji-only comments.** 18 comments contain only emoji. Under SQL Server's default collation these compare as equal to an empty string, so blank-text checks need a binary collation.
- **Misspelt columns.** The products file spells two columns `product_name_lenght` and `product_description_lenght`. The raw table keeps the source names.
