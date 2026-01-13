-- Task A: Monthly Financials
-- Assumptions:
-- 1) Revenue is based on completed, non-returned order items.
-- 2) Orders are counted as distinct order_id with at least one completed item (to avoid dups)
-- 3) Date is based on order_items.created_at

WITH completed_items AS (
	SELECT
    		oi.order_id
		, oi.sale_price
		, DATE_TRUNC(DATE(oi.created_at), MONTH) AS month
	FROM 
		`bigquery-public-data.thelook_ecommerce.order_items` oi	
	WHERE true
	AND	oi.status = 'Complete'
	AND oi.returned_at IS NULL
),

monthly_agg AS (
	SELECT
 		month
		, SUM(sale_price) AS revenue
		, COUNT(DISTINCT order_id) AS orders
    		, COUNT(*) AS units
	FROM 
		completed_items
  GROUP BY month
),

final AS (
	SELECT
	month
	, revenue
	, orders
	, units
	, SAFE_DIVIDE(revenue, orders) AS aov
	, LAG(revenue) OVER (ORDER BY month) AS prev_month_revenue
  FROM monthly_agg
)

SELECT
	month
	, revenue
	, orders
	, units
	, aov
  	, SAFE_DIVIDE(revenue - prev_month_revenue, prev_month_revenue) 
				AS mom_revenue_growth
FROM 
	final
ORDER BY month;