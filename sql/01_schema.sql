-- Harbour & Home retail database schema.
-- 6 tables, 3NF. Raw tables loaded as-is; cleaning happens in views (03_clean_views.sql).
-- state_lookup is a small reference table used to fix messy state spellings
-- via a JOIN instead of a big CASE expression - one place to update if a
-- new spelling shows up, instead of editing every query that touches state.

PRAGMA foreign_keys = ON;

DROP TABLE IF EXISTS returns;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS state_lookup;

CREATE TABLE customers (
    customer_id   INTEGER PRIMARY KEY,
    first_name    TEXT NOT NULL,
    last_name     TEXT NOT NULL,
    email         TEXT NOT NULL,
    state         TEXT,
    signup_date   TEXT            -- ISO date, NULL if missing
);

CREATE TABLE products (
    product_id    INTEGER PRIMARY KEY,
    product_name  TEXT NOT NULL,
    category      TEXT NOT NULL,
    unit_price    REAL NOT NULL CHECK (unit_price > 0),
    unit_cost     REAL NOT NULL CHECK (unit_cost >= 0)
);

CREATE TABLE orders (
    order_id      INTEGER PRIMARY KEY,
    customer_id   INTEGER NOT NULL REFERENCES customers(customer_id),
    order_date    TEXT NOT NULL,   -- ISO date
    status        TEXT NOT NULL,   -- mixed case in source, see clean_orders
    channel       TEXT NOT NULL
);

CREATE TABLE order_items (
    order_item_id INTEGER PRIMARY KEY,
    order_id      INTEGER NOT NULL REFERENCES orders(order_id),
    product_id    INTEGER NOT NULL REFERENCES products(product_id),
    quantity      INTEGER NOT NULL,   -- some rows are 0/negative, filtered later
    unit_price    REAL NOT NULL,      -- price at time of sale
    discount      REAL NOT NULL CHECK (discount >= 0 AND discount < 1)
);

CREATE TABLE returns (
    return_id       INTEGER PRIMARY KEY,
    order_item_id   INTEGER NOT NULL REFERENCES order_items(order_item_id),
    return_date     TEXT NOT NULL,
    reason          TEXT NOT NULL
);

-- raw_spelling is always UPPER(TRIM(...)) of a spelling found in customers.state
CREATE TABLE state_lookup (
    raw_spelling    TEXT PRIMARY KEY,
    standard_state  TEXT NOT NULL
);

-- indexes on join/filter columns
CREATE INDEX idx_orders_customer_id     ON orders(customer_id);
CREATE INDEX idx_orders_order_date      ON orders(order_date);
CREATE INDEX idx_order_items_order_id   ON order_items(order_id);
CREATE INDEX idx_order_items_product_id ON order_items(product_id);
CREATE INDEX idx_returns_order_item_id  ON returns(order_item_id);
