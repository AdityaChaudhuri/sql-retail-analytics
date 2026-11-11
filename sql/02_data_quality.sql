-- Profiling the RAW tables. Nothing gets fixed here - that's 03_clean_views.sql.
-- @section/@title mark blocks that run_queries.py pulls into results.md.

-- @section Overview

-- @title Row counts
SELECT 'customers' AS table_name, COUNT(*) AS rows FROM customers
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'returns', COUNT(*) FROM returns;

-- @section Content issues

-- how many raw state spellings actually resolve against state_lookup
-- @title State spellings vs. standard codes
SELECT
    COUNT(DISTINCT c.state) AS raw_spellings,
    COUNT(DISTINCT sl.standard_state) AS standard_codes,
    SUM(CASE WHEN sl.standard_state IS NULL THEN 1 ELSE 0 END) AS unmapped_rows
FROM customers c
LEFT JOIN state_lookup sl ON sl.raw_spelling = UPPER(TRIM(c.state));

-- every spelling grouped under the code it resolves to
-- @title Spelling variants by standard state
SELECT sl.standard_state, c.state AS raw_spelling, COUNT(*) AS n
FROM customers c
JOIN state_lookup sl ON sl.raw_spelling = UPPER(TRIM(c.state))
GROUP BY sl.standard_state, c.state
ORDER BY sl.standard_state, n DESC;

-- same email once case/whitespace is stripped = same person, signed up twice
-- @title Possible duplicate signups (same email, different case/whitespace)
SELECT LOWER(TRIM(email)) AS email_norm, COUNT(*) AS n_accounts,
       GROUP_CONCAT(customer_id) AS customer_ids
FROM customers
GROUP BY email_norm
HAVING COUNT(*) > 1
ORDER BY n_accounts DESC;

-- @title Customers with missing signup_date
SELECT COUNT(*) AS customers_missing_signup_date
FROM customers
WHERE signup_date IS NULL OR TRIM(signup_date) = '';

-- normalised status next to every raw spelling that rolls up into it
-- @title Order status variants
SELECT
    LOWER(TRIM(status)) AS status_clean,
    COUNT(*) AS n,
    GROUP_CONCAT(DISTINCT status) AS raw_variants
FROM orders
GROUP BY status_clean
ORDER BY n DESC;

-- @section Structural issues

-- @title Invalid order quantities
SELECT quantity, COUNT(*) AS n
FROM order_items
WHERE quantity <= 0
GROUP BY quantity
ORDER BY quantity;

-- orders with nothing in them, plus anything pointing at a row that doesn't exist
-- @title Integrity check: empty orders and dangling references
SELECT
    (SELECT COUNT(*) FROM orders o
       WHERE NOT EXISTS (SELECT 1 FROM order_items oi WHERE oi.order_id = o.order_id)) AS orders_with_no_items,
    (SELECT COUNT(*) FROM order_items oi
       WHERE NOT EXISTS (SELECT 1 FROM products p WHERE p.product_id = oi.product_id)) AS orphaned_product_refs,
    (SELECT COUNT(*) FROM order_items oi
       WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.order_id = oi.order_id)) AS orphaned_order_refs,
    (SELECT COUNT(*) FROM returns r
       WHERE NOT EXISTS (SELECT 1 FROM order_items oi WHERE oi.order_item_id = r.order_item_id)) AS orphaned_return_refs;
