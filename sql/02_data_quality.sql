-- Data-quality profiling on the RAW tables. Nothing gets fixed here.
-- @title marks blocks that run_queries.py pulls into results.md.

-- DQ1: row counts
-- @title Row counts
SELECT 'customers' AS table_name, COUNT(*) AS rows FROM customers
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'returns', COUNT(*) FROM returns;

-- DQ2: state spellings vs the 8 real states
-- @title State label inconsistencies
SELECT COUNT(DISTINCT state) AS distinct_state_spellings,
       COUNT(DISTINCT UPPER(TRIM(
           CASE
               WHEN UPPER(TRIM(state)) IN ('NSW','N.S.W.','NEW SOUTH WALES') THEN 'NSW'
               WHEN UPPER(TRIM(state)) IN ('VIC','VICTORIA','VIC.') THEN 'VIC'
               WHEN UPPER(TRIM(state)) IN ('QLD','QUEENSLAND') THEN 'QLD'
               WHEN UPPER(TRIM(state)) IN ('WA','WESTERN AUSTRALIA') THEN 'WA'
               WHEN UPPER(TRIM(state)) IN ('SA','SOUTH AUSTRALIA') THEN 'SA'
               WHEN UPPER(TRIM(state)) IN ('TAS','TASMANIA') THEN 'TAS'
               WHEN UPPER(TRIM(state)) IN ('ACT','CANBERRA') THEN 'ACT'
               WHEN UPPER(TRIM(state)) IN ('NT','NORTHERN TERRITORY') THEN 'NT'
               ELSE UPPER(TRIM(state))
           END
       ))) AS distinct_clean_states
FROM customers;

-- raw spellings grouped under their standard code
-- @title State label spellings by standard code
SELECT
    CASE
        WHEN UPPER(TRIM(state)) IN ('NSW','N.S.W.','NEW SOUTH WALES') THEN 'NSW'
        WHEN UPPER(TRIM(state)) IN ('VIC','VICTORIA','VIC.') THEN 'VIC'
        WHEN UPPER(TRIM(state)) IN ('QLD','QUEENSLAND') THEN 'QLD'
        WHEN UPPER(TRIM(state)) IN ('WA','WESTERN AUSTRALIA') THEN 'WA'
        WHEN UPPER(TRIM(state)) IN ('SA','SOUTH AUSTRALIA') THEN 'SA'
        WHEN UPPER(TRIM(state)) IN ('TAS','TASMANIA') THEN 'TAS'
        WHEN UPPER(TRIM(state)) IN ('ACT','CANBERRA') THEN 'ACT'
        WHEN UPPER(TRIM(state)) IN ('NT','NORTHERN TERRITORY') THEN 'NT'
        ELSE UPPER(TRIM(state))
    END AS standard_state,
    state AS raw_spelling,
    COUNT(*) AS n
FROM customers
GROUP BY standard_state, raw_spelling
ORDER BY standard_state, n DESC;

-- DQ3: duplicate accounts (same email, different case/whitespace)
-- @title Duplicate customer accounts (same email, different case/whitespace)
SELECT LOWER(TRIM(email)) AS email_norm, COUNT(*) AS n_accounts,
       GROUP_CONCAT(customer_id) AS customer_ids
FROM customers
GROUP BY email_norm
HAVING COUNT(*) > 1
ORDER BY n_accounts DESC;

-- DQ4: missing signup dates
-- @title Customers with missing signup_date
SELECT COUNT(*) AS customers_missing_signup_date
FROM customers
WHERE signup_date IS NULL OR TRIM(signup_date) = '';

-- DQ5: order status casing
-- @title Order status casing
SELECT status AS raw_status, LOWER(TRIM(status)) AS normalised_status, COUNT(*) AS n
FROM orders
GROUP BY raw_status
ORDER BY normalised_status, n DESC;

-- impact of a naive case-sensitive status filter
-- @title Completed orders lost without case-insensitive matching
SELECT
    SUM(CASE WHEN LOWER(TRIM(status)) = 'completed' THEN 1 ELSE 0 END) AS completed_case_insensitive,
    SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed_exact_match_only
FROM orders;

-- DQ6: invalid quantities
-- @title Order items with invalid quantity
SELECT quantity, COUNT(*) AS n
FROM order_items
WHERE quantity <= 0
GROUP BY quantity
ORDER BY quantity;

-- DQ7: orders with no line items (anti-join)
-- @title Orders with zero line items
SELECT COUNT(*) AS orders_with_no_items
FROM orders o
WHERE NOT EXISTS (SELECT 1 FROM order_items oi WHERE oi.order_id = o.order_id);

-- DQ8: orphaned foreign keys
-- @title Orphaned foreign key references
SELECT
    (SELECT COUNT(*) FROM order_items oi
       WHERE NOT EXISTS (SELECT 1 FROM products p WHERE p.product_id = oi.product_id)) AS orphaned_product_refs,
    (SELECT COUNT(*) FROM order_items oi
       WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.order_id = oi.order_id)) AS orphaned_order_refs,
    (SELECT COUNT(*) FROM returns r
       WHERE NOT EXISTS (SELECT 1 FROM order_items oi WHERE oi.order_item_id = r.order_item_id)) AS orphaned_return_refs;
