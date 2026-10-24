# E-commerce Analytics Warehouse

A SQL Server data warehouse built from about 100,000 real orders on Olist, a Brazilian e-commerce marketplace (2016–2018). It turns nine raw CSV files into a tested star schema. That schema is used to analyse revenue, repeat customers, seller performance and delivery.

## Business questions

- What drives monthly revenue, and how much of what customers pay is freight?
- How do repeat customers differ from one-time buyers?
- Which sellers deliver late, and how does late delivery affect review scores?
- Which product categories sell most, and which receive the worst reviews?
- Do payments reconcile to item prices plus freight for every order?

## Project status

| Step | Work | Status |
|---|---|---|
| 1 | Setup, raw load and load checks | Done |
| 2 | Staging and data profiling | Next |
| 3 | Star schema (dimensions and facts) | Planned |
| 4 | Business analysis queries | Planned |
| 5 | Reconciliation controls and dashboard | Planned |

## Architecture

| Schema | Purpose |
|---|---|
| `raw` | The source CSV files loaded exactly as they are, with every column stored as text |
| `stg` | Cleaned, typed and renamed copies of the raw tables |
| `dw` | Star schema: dimensions and facts with documented grains |
| `mart` | Summary tables for reporting |
| `audit` | Load history, and the expected record count and checksum of every source file |

Every load is checked against [`data/source_manifest.csv`](data/source_manifest.csv). That file records how many records each source file holds, counted independently with Python's CSV parser. If a raw table's row count doesn't match, the build stops.

## How to run

**Requirements:** Windows, SQL Server 2017 or later (LocalDB, Express or Developer edition), `sqlcmd`, Python 3.8 or later.

```
python scripts/get_data.py
powershell -ExecutionPolicy Bypass -File scripts\build.ps1
```

The build uses SQL Server LocalDB by default. To use another instance:

```
powershell -ExecutionPolicy Bypass -File scripts\build.ps1 -Server "localhost\SQLEXPRESS"
```

The build can be rerun at any time. It replaces the data rather than duplicating it, and it keeps the load history in `audit.load_log`.

`BULK INSERT` reads files from the SQL Server machine, so the server must be able to see the project folder. That's always true for LocalDB and for a local instance.

To run the scripts in SSMS instead, open them in the order listed in [`scripts/build.ps1`](scripts/build.ps1). In `sql/01_raw/03_run_load.sql`, replace `$(DataDir)` with the full path to the `data` folder.

## Repository structure

```text
data/
  README.md              source, licence and notes on the files
  source_manifest.csv    expected size, checksum and record count of each file
  raw/                   CSV files (downloaded, not committed)
scripts/
  get_data.py            downloads and verifies the source files
  build.ps1              runs every SQL script in order and stops on the first error
sql/
  00_setup/              database, schemas and audit tables
  01_raw/                raw tables and the load procedure
tests/
  01_raw_load_checks.sql row counts reconciled to the source files
```

## Data source

[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce), licensed under CC BY-NC-SA 4.0. See [`data/README.md`](data/README.md) for the files and their quirks.
