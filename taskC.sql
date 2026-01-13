WITH completed_orders AS (
  SELECT
    o.user_id
    , DATE(oi.created_at) AS order_date
    , DATE_TRUNC(DATE(oi.created_at), MONTH) AS month
  FROM `bigquery-public-data.thelook_ecommerce.order_items` oi
  JOIN `bigquery-public-data.thelook_ecommerce.orders` o
  ON oi.order_id = o.order_id
  WHERE true
    AND oi.returned_at IS NULL
),

monthly_last_purchase AS (
  SELECT
    user_id
    , month
    , MAX(order_date) AS last_purchase_date
  FROM completed_orders
  GROUP BY user_id, month
),

churn_flag AS (
  SELECT
    mlp.user_id
    , mlp.month
    , mlp.last_purchase_date
    , CASE
      WHEN NOT EXISTS (
        SELECT 1
        FROM completed_orders co
        WHERE true
          AND co.user_id = mlp.user_id
          AND co.order_date > mlp.last_purchase_date
          AND co.order_date <= DATE_ADD(mlp.last_purchase_date, INTERVAL 90 DAY)
      )
      THEN 1
      ELSE 0
      END AS is_churned_90d
  FROM monthly_last_purchase mlp
  WHERE DATE_ADD(mlp.last_purchase_date, INTERVAL 90 DAY) <= 
                (SELECT MAX(order_date) FROM completed_orders)
)

SELECT
  month
  , COUNT(DISTINCT user_id) AS active_customers
  , COUNT(DISTINCT CASE WHEN is_churned_90d = 1 THEN user_id END) AS churned_customers_90d
  , SAFE_DIVIDE(
      COUNT(DISTINCT CASE WHEN is_churned_90d = 1 THEN user_id END)
      , COUNT(DISTINCT user_id)
  ) AS churn_rate_90d
FROM churn_flag
GROUP BY month
ORDER BY month;
