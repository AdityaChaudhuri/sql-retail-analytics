-- Business questions Q1-Q12, against the cleaned views in 03_clean_views.sql.
-- "Sales" means completed orders only unless noted.

-- @title Q1: Monthly revenue trend and month-over-month growth
WITH monthly AS (
    SELECT strftime('%Y-%m', order_date) AS month, SUM(revenue) AS revenue
    FROM v_sales
    WHERE status = 'completed'
    GROUP BY month
)
SELECT
    month,
    ROUND(revenue, 2) AS revenue,
    ROUND(revenue - LAG(revenue) OVER (ORDER BY month), 2) AS revenue_change,
    ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
          / LAG(revenue) OVER (ORDER BY month), 1) AS pct_growth
FROM monthly
ORDER BY month;

-- @title Q2: Revenue and margin by category
SELECT
    category,
    ROUND(SUM(revenue), 2) AS revenue,
    ROUND(SUM(margin), 2) AS margin,
    ROUND(100.0 * SUM(margin) / SUM(revenue), 1) AS margin_pct,
    ROUND(100.0 * SUM(revenue) / (SELECT SUM(revenue) FROM v_sales WHERE status = 'completed'), 1) AS pct_of_total_revenue
FROM v_sales
WHERE status = 'completed'
GROUP BY category
ORDER BY revenue DESC;

-- @title Q3: Top 10 customers by lifetime value
SELECT
    c.customer_id,
    c.first_name,
    c.last_name,
    c.state,
    COUNT(DISTINCT s.order_id) AS n_orders,
    ROUND(SUM(s.revenue), 2) AS lifetime_value
FROM v_sales s
JOIN v_customers_clean c ON c.customer_id = s.customer_id AND c.is_primary_account = 1
WHERE s.status = 'completed'
GROUP BY c.customer_id
ORDER BY lifetime_value DESC
LIMIT 10;

-- @title Q4: Revenue by state
SELECT
    customer_state AS state,
    COUNT(DISTINCT customer_id) AS n_customers,
    ROUND(SUM(revenue), 2) AS revenue
FROM v_sales
WHERE status = 'completed'
GROUP BY state
ORDER BY revenue DESC;

-- @title Q5: Return rate by category
SELECT
    p.category,
    COUNT(*) AS items_sold,
    SUM(CASE WHEN r.return_id IS NOT NULL THEN 1 ELSE 0 END) AS items_returned,
    ROUND(100.0 * SUM(CASE WHEN r.return_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS return_rate_pct
FROM order_items oi
JOIN v_orders_clean o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
LEFT JOIN returns r ON r.order_item_id = oi.order_item_id
WHERE o.status = 'completed' AND oi.quantity > 0
GROUP BY p.category
ORDER BY return_rate_pct DESC;

-- @title Q6: Top return reasons (share of all returns)
SELECT
    reason,
    COUNT(*) AS n_returns,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_returns
FROM returns
GROUP BY reason
ORDER BY n_returns DESC;

-- @title Q7: Repeat purchase rate among buying customers
WITH customer_orders AS (
    SELECT customer_id, COUNT(DISTINCT order_id) AS n_orders
    FROM v_sales
    WHERE status = 'completed'
    GROUP BY customer_id
)
SELECT
    COUNT(*) AS buying_customers,
    SUM(CASE WHEN n_orders >= 2 THEN 1 ELSE 0 END) AS repeat_customers,
    ROUND(100.0 * SUM(CASE WHEN n_orders >= 2 THEN 1 ELSE 0 END) / COUNT(*), 1) AS repeat_rate_pct
FROM customer_orders;

-- @title Q8: Average order value by channel
SELECT
    channel,
    COUNT(DISTINCT order_id) AS n_orders,
    ROUND(SUM(revenue) / COUNT(DISTINCT order_id), 2) AS avg_order_value
FROM v_sales
WHERE status = 'completed'
GROUP BY channel
ORDER BY avg_order_value DESC;

-- @title Q9: Products that never sold
SELECT p.product_id, p.product_name, p.category
FROM products p
WHERE NOT EXISTS (
    SELECT 1
    FROM order_items oi
    JOIN v_orders_clean o ON o.order_id = oi.order_id
    WHERE oi.product_id = p.product_id AND oi.quantity > 0 AND o.status = 'completed'
);

-- @title Q10: Customer segmentation (recency/frequency as of 2025-12-31)
WITH last_order AS (
    SELECT customer_id, MAX(order_date) AS last_order_date, COUNT(DISTINCT order_id) AS n_orders
    FROM v_sales
    WHERE status = 'completed'
    GROUP BY customer_id
),
scored AS (
    SELECT
        customer_id,
        n_orders,
        CAST(julianday('2025-12-31') - julianday(last_order_date) AS INTEGER) AS days_since_last_order
    FROM last_order
)
SELECT
    CASE
        WHEN days_since_last_order <= 60 THEN 'Active'
        WHEN days_since_last_order <= 120 THEN 'At risk'
        ELSE 'Lapsed'
    END AS segment,
    COUNT(*) AS n_customers,
    ROUND(AVG(n_orders), 1) AS avg_orders_per_customer
FROM scored
GROUP BY segment
ORDER BY n_customers DESC;

-- @title Q11: Best seller (by revenue) in each category
WITH product_sales AS (
    SELECT product_id, product_name, category, SUM(quantity) AS units_sold, SUM(revenue) AS revenue
    FROM v_sales
    WHERE status = 'completed'
    GROUP BY product_id
),
ranked AS (
    SELECT *, RANK() OVER (PARTITION BY category ORDER BY revenue DESC) AS rnk
    FROM product_sales
)
SELECT category, product_name, units_sold, ROUND(revenue, 2) AS revenue
FROM ranked
WHERE rnk = 1
ORDER BY revenue DESC;

-- @title Q12: Black Friday week (Nov 24-30) vs rest of year
WITH bucketed AS (
    SELECT *,
        CASE WHEN order_date BETWEEN '2025-11-24' AND '2025-11-30'
             THEN 'Black Friday week' ELSE 'Rest of year' END AS period
    FROM v_sales
    WHERE status = 'completed'
)
SELECT
    period,
    ROUND(SUM(revenue), 2) AS revenue,
    ROUND(SUM(margin), 2) AS margin,
    ROUND(100.0 * SUM(margin) / SUM(revenue), 1) AS margin_pct,
    ROUND(100.0 * AVG(discount), 1) AS avg_discount_pct
FROM bucketed
GROUP BY period
ORDER BY period;
