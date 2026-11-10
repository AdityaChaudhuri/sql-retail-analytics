"""
Builds retail.db from sql/01_schema.sql and the CSVs in ./data.

Run:  python build_db.py
"""
import csv
import os
import sqlite3

ROOT = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(ROOT, "retail.db")
SCHEMA_PATH = os.path.join(ROOT, "sql", "01_schema.sql")
DATA_DIR = os.path.join(ROOT, "data")

TABLES = [
    ("customers.csv", "customers",
     ["customer_id", "first_name", "last_name", "email", "state", "signup_date"]),
    ("products.csv", "products",
     ["product_id", "product_name", "category", "unit_price", "unit_cost"]),
    ("orders.csv", "orders",
     ["order_id", "customer_id", "order_date", "status", "channel"]),
    ("order_items.csv", "order_items",
     ["order_item_id", "order_id", "product_id", "quantity", "unit_price", "discount"]),
    ("returns.csv", "returns",
     ["return_id", "order_item_id", "return_date", "reason"]),
]

# columns to coerce to int (CSV values are all strings otherwise)
INT_COLS = {"customer_id", "product_id", "order_id", "order_item_id", "quantity", "return_id"}


def load_csv(path, columns):
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        rows = []
        for row in reader:
            values = []
            for col in columns:
                v = row[col]
                if v == "":
                    values.append(None)
                elif col in INT_COLS:
                    values.append(int(v))
                else:
                    values.append(v)
            rows.append(tuple(values))
        return rows


def main():
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)

    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys = ON;")

    with open(SCHEMA_PATH, encoding="utf-8") as f:
        conn.executescript(f.read())

    # order matters: FK dependencies first
    for csv_name, table, columns in TABLES:
        rows = load_csv(os.path.join(DATA_DIR, csv_name), columns)
        placeholders = ", ".join("?" for _ in columns)
        conn.executemany(
            f"INSERT INTO {table} ({', '.join(columns)}) VALUES ({placeholders})",
            rows,
        )
        print(f"loaded {len(rows):>5} rows into {table}")

    conn.commit()
    conn.close()
    print(f"\n{DB_PATH} built successfully.")


if __name__ == "__main__":
    main()
