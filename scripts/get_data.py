"""Download the Olist dataset into data/raw and check it against data/source_manifest.csv.

Usage:
    python scripts/get_data.py                   download (if needed), unpack and verify
    python scripts/get_data.py --zip PATH        unpack a zip downloaded manually from Kaggle, then verify
    python scripts/get_data.py --write-manifest  record the files in data/raw as the expected version

Uses only the Python standard library.
"""
import argparse
import csv
import hashlib
import sys
import urllib.request
import zipfile
from pathlib import Path

DATASET_URL = "https://www.kaggle.com/api/v1/datasets/download/olistbr/brazilian-ecommerce"

DATA_DIR = Path(__file__).resolve().parent.parent / "data"
RAW_DIR = DATA_DIR / "raw"
MANIFEST = DATA_DIR / "source_manifest.csv"
MANIFEST_FIELDS = ["file_name", "size_bytes", "sha256", "record_count"]

SOURCE_FILES = [
    "olist_customers_dataset.csv",
    "olist_geolocation_dataset.csv",
    "olist_order_items_dataset.csv",
    "olist_order_payments_dataset.csv",
    "olist_order_reviews_dataset.csv",
    "olist_orders_dataset.csv",
    "olist_products_dataset.csv",
    "olist_sellers_dataset.csv",
    "product_category_name_translation.csv",
]


def download(target):
    print(f"Downloading {DATASET_URL}")
    with urllib.request.urlopen(DATASET_URL) as response, open(target, "wb") as out:
        while chunk := response.read(1 << 20):
            out.write(chunk)


def unpack(zip_path):
    with zipfile.ZipFile(zip_path) as archive:
        missing = [name for name in SOURCE_FILES if name not in archive.namelist()]
        if missing:
            sys.exit(f"{zip_path} is missing: {', '.join(missing)}")
        for name in SOURCE_FILES:
            archive.extract(name, RAW_DIR)
    print(f"Unpacked {len(SOURCE_FILES)} files into {RAW_DIR}")


def describe(path):
    """Size, SHA-256 checksum and number of data records (not lines) in one CSV file."""
    sha256 = hashlib.sha256(path.read_bytes()).hexdigest()
    # Count with a CSV parser: some review comments contain line breaks inside quotes,
    # so the number of lines is higher than the number of records.
    with path.open(encoding="utf-8-sig", newline="") as f:
        record_count = sum(1 for _ in csv.reader(f)) - 1  # minus the header row
    return {"file_name": path.name, "size_bytes": path.stat().st_size, "sha256": sha256, "record_count": record_count}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--zip", type=Path, help="zip file downloaded manually from Kaggle")
    parser.add_argument("--write-manifest", action="store_true", help="overwrite data/source_manifest.csv")
    args = parser.parse_args()

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    if args.zip:
        unpack(args.zip)
    elif not all((RAW_DIR / name).exists() for name in SOURCE_FILES):
        zip_path = RAW_DIR / "brazilian-ecommerce.zip"
        download(zip_path)
        unpack(zip_path)

    actual = [describe(RAW_DIR / name) for name in SOURCE_FILES]

    if args.write_manifest:
        with MANIFEST.open("w", encoding="utf-8", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=MANIFEST_FIELDS, lineterminator="\n")
            writer.writeheader()
            writer.writerows(actual)
        print(f"Wrote {MANIFEST}")
        return

    with MANIFEST.open(encoding="utf-8", newline="") as f:
        expected = {row["file_name"]: row for row in csv.DictReader(f)}

    problems = 0
    for file in actual:
        exp = expected.get(file["file_name"])
        if exp is None:
            status = "NOT IN MANIFEST"
        elif exp["sha256"] != file["sha256"]:
            status = "CHECKSUM DIFFERS"
        else:
            status = "OK"
        problems += status != "OK"
        print(f"{status:<16} {file['file_name']:<40} {file['record_count']:>9,} records")

    if problems:
        sys.exit(f"{problems} file(s) do not match {MANIFEST.name}; the dataset may have changed on Kaggle.")
    print("All files match the manifest.")


if __name__ == "__main__":
    main()
