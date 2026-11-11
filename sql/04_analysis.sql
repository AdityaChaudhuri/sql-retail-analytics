-- Business questions, against the clean views in 03_clean_views.sql.
-- "Sales" means completed orders only unless noted. Grouped into two
-- sections (@section) so results.md reads like a short report, not a flat list.

-- @section Customer insights

-- @title Monthly revenue trend (with running total)
WITH monthly AS (
    SELECT strftime('%Y-%m', order_date) AS month, SUM(revenue) AS revenue,
           COUNT(DISTINCT order_id) AS n_orders
    FROM fact_sales
    WHERE status = 'completed'
    GROUP BY month
)
SELECT
    month,
    n_orders,
    ROUND(revenue, 2) AS revenue,
    ROUND(SUM(revenue) OVER (ORDER BY month), 2) AS cumulative_revenue
FROM monthly
ORDER BY month;

-- @title Top customers by revenue and by order count
WITH per_customer AS (
    SELECT c.customer_id, c.first_name, c.last_name, c.state,
           SUM(s.revenue) AS revenue, COUNT(DISTINCT s.order_id) AS n_orders
    FROM fact_sales s
    JOIN clean_customers c ON c.customer_id = s.customer_id AND c.is_primary_account = 1
    WHERE s.status = 'completed'
    GROUP BY c.customer_id
),
ranked AS (
    SELECT *,
        DENSE_RANK() OVER (ORDER BY revenue DESC) AS revenue_rank,
        DENSE_RANK() OVER (ORDER BY n_orders DESC) AS order_count_rank
    FROM per_customer
)
SELECT 'By revenue' AS ranked_by, customer_id, first_name, last_name, state,
       n_orders, ROUND(revenue, 2) AS revenue
FROM ranked WHERE revenue_rank <= 5
UNION ALL
SELECT 'By order count', customer_id, first_name, last_name, state,
       n_orders, ROUND(revenue, 2)
FROM ranked WHERE order_count_rank <= 5
ORDER BY ranked_by, revenue DESC;

-- @title Revenue and customer reach by state
SELECT
    customer_state AS state,
    COUNT(DISTINCT customer_id) AS n_customers,
    ROUND(SUM(revenue), 2) AS revenue,
    ROUND(SUM(revenue) / COUNT(DISTINCT customer_id), 2) AS avg_revenue_per_customer
FROM fact_sales
WHERE status = 'completed'
GROUP BY state
ORDER BY revenue DESC;

-- @title Customer lifecycle stage (as of 2025-12-31)
WITH order_span AS (
    SELECT customer_id, MAX(order_date) AS last_order_date, COUNT(DISTINCT order_id) AS n_orders
    FROM fact_sales
    WHERE status = 'completed'
    GROUP BY customer_id
),
scored AS (
    SELECT
        customer_id,
        n_orders,
        CAST(julianday('2025-12-31') - julianday(last_order_date) AS INTEGER) AS days_since_last_order
    FROM order_span
)
SELECT
    CASE
        WHEN days_since_last_order <= 30 THEN 'New'
        WHEN days_since_last_order <= 90 THEN 'Active'
        WHEN days_since_last_order <= 180 THEN 'At risk'
        ELSE 'Lapsed'
    END AS lifecycle_stage,
    COUNT(*) AS n_customers,
    ROUND(AVG(n_orders), 1) AS avg_orders_per_customer
FROM scored
GROUP BY lifecycle_stage
ORDER BY n_customers DESC;

-- @title Repeat purchase rate
WITH customer_orders AS (
    SELECT customer_id, COUNT(DISTINCT order_id) AS n_orders
    FROM fact_sales
    WHERE status = 'completed'
    GROUP BY customer_id
)
SELECT
    COUNT(*) AS buying_customers,
    SUM(CASE WHEN n_orders >= 2 THEN 1 ELSE 0 END) AS repeat_customers,
    ROUND(100.0 * SUM(CASE WHEN n_orders >= 2 THEN 1 ELSE 0 END) / COUNT(*), 1) AS repeat_rate_pct,
    ROUND(AVG(CASE WHEN n_orders >= 2 THEN n_orders END), 1) AS avg_orders_per_repeat_customer
FROM customer_orders;

-- @section Product & operations insights

-- @title Category revenue, margin and share of total
WITH by_category AS (
    SELECT category, SUM(revenue) AS revenue, SUM(margin) AS margin
    FROM fact_sales
    WHERE status = 'completed'
    GROUP BY category
)
SELECT
    category,
    ROUND(revenue, 2) AS revenue,
    ROUND(margin, 2) AS margin,
    ROUND(100.0 * margin / revenue, 1) AS margin_pct,
    RANK() OVER (ORDER BY margin / revenue DESC) AS margin_rank,
    ROUND(100.0 * revenue / SUM(revenue) OVER (), 1) AS pct_of_total_revenue
FROM by_category
ORDER BY revenue DESC;

-- @title Best-selling products overall (top 5 by revenue)
WITH product_sales AS (
    SELECT product_id, product_name, category, SUM(quantity) AS units_sold, SUM(revenue) AS revenue
    FROM fact_sales
    WHERE status = 'completed'
    GROUP BY product_id
)
SELECT product_name, category, units_sold, ROUND(revenue, 2) AS revenue
FROM (SELECT *, ROW_NUMBER() OVER (ORDER BY revenue DESC) AS rn FROM product_sales)
WHERE rn <= 5
ORDER BY revenue DESC;

-- @title Underperforming and never-sold products
WITH product_sales AS (
    SELECT p.product_id, p.product_name, p.category, COALESCE(SUM(fs.revenue), 0) AS revenue
    FROM products p
    LEFT JOIN fact_sales fs ON fs.product_id = p.product_id AND fs.status = 'completed'
    GROUP BY p.product_id
)
SELECT product_name, category, 'Never sold' AS flag, ROUND(revenue, 2) AS revenue
FROM product_sales
WHERE revenue = 0
UNION ALL
SELECT product_name, category, 'Bottom 5 by revenue', ROUND(revenue, 2)
FROM (SELECT *, ROW_NUMBER() OVER (ORDER BY revenue ASC) AS rn FROM product_sales WHERE revenue > 0)
WHERE rn <= 5
ORDER BY flag, revenue;

-- @title Return rate by category
SELECT
    p.category,
    COUNT(*) AS items_sold,
    SUM(CASE WHEN r.return_id IS NOT NULL THEN 1 ELSE 0 END) AS items_returned,
    ROUND(100.0 * SUM(CASE WHEN r.return_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS return_rate_pct
FROM order_items oi
JOIN clean_orders o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
LEFT JOIN returns r ON r.order_item_id = oi.order_item_id
WHERE o.status = 'completed' AND oi.quantity > 0
GROUP BY p.category
ORDER BY return_rate_pct DESC;

-- @title Return reasons, share of total
SELECT
    reason,
    COUNT(*) AS n_returns,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_returns
FROM returns
GROUP BY reason
ORDER BY n_returns DESC;

-- @title Channel performance and revenue share
SELECT
    channel,
    COUNT(DISTINCT order_id) AS n_orders,
    ROUND(SUM(revenue) / COUNT(DISTINCT order_id), 2) AS avg_order_value,
    ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1) AS revenue_share_pct
FROM fact_sales
WHERE status = 'completed'
GROUP BY channel
ORDER BY avg_order_value DESC;

-- @title Discount depth breakdown
SELECT
    discount_bucket,
    COUNT(*) AS n_lines,
    ROUND(SUM(revenue), 2) AS revenue,
    ROUND(100.0 * AVG(discount), 1) AS avg_discount_pct
FROM fact_sales
WHERE status = 'completed'
GROUP BY discount_bucket
ORDER BY revenue DESC;

-- @title Black Friday week (Nov 24-30) vs. rest of year
WITH bucketed AS (
    SELECT *,
        CASE WHEN order_date BETWEEN '2025-11-24' AND '2025-11-30'
             THEN 'Black Friday week' ELSE 'Rest of year' END AS period
    FROM fact_sales
    WHERE status = 'completed'
),
day_counts AS (
    SELECT 'Black Friday week' AS period, 7 AS n_days
    UNION ALL
    SELECT 'Rest of year', CAST(julianday('2025-12-31') - julianday('2025-01-01') AS INTEGER) + 1 - 7
)
SELECT
    b.period,
    ROUND(SUM(b.revenue), 2) AS revenue,
    ROUND(SUM(b.margin), 2) AS margin,
    ROUND(100.0 * SUM(b.margin) / SUM(b.revenue), 1) AS margin_pct,
    ROUND(SUM(b.revenue) / d.n_days, 2) AS avg_daily_revenue
FROM bucketed b
JOIN day_counts d ON d.period = b.period
GROUP BY b.period, d.n_days
ORDER BY b.period;
