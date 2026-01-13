with completed_orders as (
  SELECT
    oi.order_id
    , o.user_id
    , oi.sale_price
    , DATE_TRUNC(DATE(oi.created_at), MONTH) as month
  FROM
    `bigquery-public-data.thelook_ecommerce.order_items` oi
  JOIN
    `bigquery-public-data.thelook_ecommerce.orders` o
  ON
    oi.order_id = o.order_id
  WHERE true
  AND oi.status = 'Complete'
),

first_purchase AS (
  SELECT
    user_id
    , MIN(month) AS first_purchase_month
  FROM
    completed_orders
  GROUP BY
    user_id
),

orders_with_flags AS (
  SELECT
    co.*
    , fp.first_purchase_month
    , CASE
      WHEN co.month = fp.first_purchase_month THEN 'new'
      ELSE 'returning' END AS customer_type
  FROM completed_orders co
  JOIN first_purchase fp
  ON co.user_id = fp.user_id
)

SELECT
  month
  , COUNT(DISTINCT user_id) AS active_customers
  , COUNT(DISTINCT CASE WHEN customer_type = 'new'
            THEN user_id END) AS new_customers
  , COUNT(DISTINCT CASE WHEN customer_type = 'returning'
            THEN user_id END) AS returning_customers
  , SAFE_DIVIDE(
    SUM(CASE WHEN customer_type = 'returning' THEN sale_price END)
    , SUM(sale_price)
  ) AS pct_revenue_from_returning
FROM orders_with_flags
GROUP BY month
ORDER BY month;