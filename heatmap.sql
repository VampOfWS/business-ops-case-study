-- heatmap
WITH completed_orders AS (        -- To determine active users
  SELECT DISTINCT
    o.user_id
    , DATE_TRUNC(DATE(oi.created_at), MONTH) AS order_month
    FROM
      `bigquery-public-data.thelook_ecommerce.order_items` oi
    JOIN
      `bigquery-public-data.thelook_ecommerce.orders` o
    ON oi.order_id = o.order_id
    WHERE true
      AND oi.status = 'Complete'
      AND oi.returned_at IS NULL
),

first_purchase AS (
  SELECT
    user_id
    , MIN(order_month) AS first_purchase_month
  FROM completed_orders
  GROUP BY user_id
),

orders_with_cohorts AS (
  SELECT
    co.user_id
    , fp.first_purchase_month
    , co.order_month
    , DATE_DIFF(
      co.order_month
      , fp.first_purchase_month
      , MONTH ) AS months_since_first_purchase
  FROM completed_orders co
  JOIN first_purchase fp
  ON co.user_id = fp.user_id
  WHERE DATE_DIFF(co.order_month, fp.first_purchase_month, MONTH) >= 0
),

cohort_sizes AS (
  SELECT
    first_purchase_month
    , COUNT(DISTINCT user_id) AS cohort_size
  FROM first_purchase
  GROUP BY first_purchase_month
),

retention AS (
  SELECT
    owc.first_purchase_month
    , owc.months_since_first_purchase
    , COUNT(DISTINCT owc.user_id) AS retained_users
  FROM orders_with_cohorts owc
  GROUP BY owc.first_purchase_month, owc.months_since_first_purchase
)

SELECT
  r.first_purchase_month
  , r.months_since_first_purchase
  , SAFE_DIVIDE(r.retained_users, cs.cohort_size) AS retention_rate
FROM retention r
JOIN cohort_sizes cs
ON r.first_purchase_month = cs.first_purchase_month
ORDER BY
  first_purchase_month, months_since_first_purchase;
