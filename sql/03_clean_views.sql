-- Cleaning layer. Raw tables stay untouched; every fix lives in a view here.

DROP VIEW IF EXISTS fact_sales;
DROP VIEW IF EXISTS clean_order_items;
DROP VIEW IF EXISTS clean_orders;
DROP VIEW IF EXISTS clean_customers;

-- State spellings resolved via state_lookup (falls back to the raw value if
-- something slips through unmapped). Duplicate signups: ROW_NUMBER picks one
-- canonical row per email, FIRST_VALUE carries that row's customer_id onto
-- every duplicate so they can all be collapsed onto it downstream.
-- Missing signup_date is left as NULL - not needed for sales analysis.
CREATE VIEW clean_customers AS
WITH ordered AS (
    SELECT
        c.customer_id,
        c.first_name,
        c.last_name,
        LOWER(TRIM(c.email)) AS email_norm,
        COALESCE(sl.standard_state, UPPER(TRIM(c.state))) AS state,
        c.signup_date,
        ROW_NUMBER() OVER (PARTITION BY LOWER(TRIM(c.email)) ORDER BY c.customer_id) AS signup_rank,
        FIRST_VALUE(c.customer_id) OVER (PARTITION BY LOWER(TRIM(c.email)) ORDER BY c.customer_id) AS primary_customer_id
    FROM customers c
    LEFT JOIN state_lookup sl ON sl.raw_spelling = UPPER(TRIM(c.state))
)
SELECT
    customer_id,
    primary_customer_id,
    first_name,
    last_name,
    email_norm AS email,
    state,
    signup_date,
    (signup_rank = 1) AS is_primary_account
FROM ordered;

-- status normalised to lowercase so a plain `= 'completed'` works everywhere
CREATE VIEW clean_orders AS
SELECT
    order_id,
    customer_id,
    order_date,
    LOWER(TRIM(status)) AS status,
    channel
FROM orders;

-- drops the handful of zero/negative quantity lines
CREATE VIEW clean_order_items AS
SELECT *
FROM order_items
WHERE quantity > 0;

-- one row per valid sold line item, fully joined and calculated, which is
-- what every query in 04_analysis.sql actually reads from. Revenue is
-- attributed to the primary_customer_id, so a duplicate signup doesn't
-- split one customer's spend across two ids. discount_bucket groups the
-- line into none/low/high so discounting can be analysed as a category,
-- not just a raw percentage.
CREATE VIEW fact_sales AS
SELECT
    oi.order_item_id,
    o.order_id,
    o.order_date,
    o.status,
    o.channel,
    c.primary_customer_id AS customer_id,
    c.state AS customer_state,
    p.product_id,
    p.product_name,
    p.category,
    oi.quantity,
    oi.unit_price,
    oi.discount,
    CASE
        WHEN oi.discount = 0 THEN 'none'
        WHEN oi.discount <= 0.10 THEN 'low'
        ELSE 'high'
    END AS discount_bucket,
    ROUND(oi.quantity * oi.unit_price * (1 - oi.discount), 2) AS revenue,
    ROUND(oi.quantity * p.unit_cost, 2) AS cost,
    ROUND(oi.quantity * oi.unit_price * (1 - oi.discount) - oi.quantity * p.unit_cost, 2) AS margin,
    EXISTS (SELECT 1 FROM returns r WHERE r.order_item_id = oi.order_item_id) AS is_returned
FROM clean_order_items oi
JOIN clean_orders o ON o.order_id = oi.order_id
JOIN clean_customers c ON c.customer_id = o.customer_id
JOIN products p ON p.product_id = oi.product_id;
