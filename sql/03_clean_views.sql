-- Cleaning layer. Raw tables stay untouched; every fix lives in a view here.

DROP VIEW IF EXISTS v_sales;
DROP VIEW IF EXISTS v_order_items_clean;
DROP VIEW IF EXISTS v_orders_clean;
DROP VIEW IF EXISTS v_customers_clean;

-- Fixes DQ2 (state spellings) and DQ3 (duplicate accounts).
-- DQ4 (missing signup_date) is left as NULL - not needed for sales analysis.
CREATE VIEW v_customers_clean AS
WITH normalised AS (
    SELECT
        customer_id,
        first_name,
        last_name,
        LOWER(TRIM(email)) AS email_norm,
        CASE
            WHEN UPPER(TRIM(state)) IN ('NSW','N.S.W.','NEW SOUTH WALES') THEN 'NSW'
            WHEN UPPER(TRIM(state)) IN ('VIC','VICTORIA','VIC.')          THEN 'VIC'
            WHEN UPPER(TRIM(state)) IN ('QLD','QUEENSLAND')               THEN 'QLD'
            WHEN UPPER(TRIM(state)) IN ('WA','WESTERN AUSTRALIA')        THEN 'WA'
            WHEN UPPER(TRIM(state)) IN ('SA','SOUTH AUSTRALIA')          THEN 'SA'
            WHEN UPPER(TRIM(state)) IN ('TAS','TASMANIA')                 THEN 'TAS'
            WHEN UPPER(TRIM(state)) IN ('ACT','CANBERRA')                 THEN 'ACT'
            WHEN UPPER(TRIM(state)) IN ('NT','NORTHERN TERRITORY')        THEN 'NT'
            ELSE UPPER(TRIM(state))
        END AS state,
        signup_date,
        MIN(customer_id) OVER (PARTITION BY LOWER(TRIM(email))) AS primary_customer_id
    FROM customers
)
SELECT
    customer_id,
    primary_customer_id,
    first_name,
    last_name,
    email_norm AS email,
    state,
    signup_date,
    (customer_id = primary_customer_id) AS is_primary_account
FROM normalised;

-- Fixes DQ5: status normalised to lowercase.
CREATE VIEW v_orders_clean AS
SELECT
    order_id,
    customer_id,
    order_date,
    LOWER(TRIM(status)) AS status,
    channel
FROM orders;

-- Fixes DQ6: drops zero/negative quantity lines.
CREATE VIEW v_order_items_clean AS
SELECT *
FROM order_items
WHERE quantity > 0;

-- One row per valid sold line item, joined and ready for analysis.
-- Revenue is attributed to the primary customer_id so duplicate accounts
-- don't split a customer's lifetime value.
CREATE VIEW v_sales AS
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
    ROUND(oi.quantity * oi.unit_price * (1 - oi.discount), 2) AS revenue,
    ROUND(oi.quantity * p.unit_cost, 2) AS cost,
    ROUND(oi.quantity * oi.unit_price * (1 - oi.discount) - oi.quantity * p.unit_cost, 2) AS margin,
    EXISTS (SELECT 1 FROM returns r WHERE r.order_item_id = oi.order_item_id) AS is_returned
FROM v_order_items_clean oi
JOIN v_orders_clean o ON o.order_id = oi.order_id
JOIN v_customers_clean c ON c.customer_id = o.customer_id
JOIN products p ON p.product_id = oi.product_id;
