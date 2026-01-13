-- TASK D: Free Shipping Impact (Proxy Analysis)
-- Output is CSV-ready for downstream analysis / visualization
-- Analysis was performed on Google Sheets

WITH base_orders AS (
  SELECT
    o.order_id
    , o.user_id
    , DATE(o.created_at) AS order_date
    , DATE_TRUNC(DATE(o.created_at), MONTH) AS order_month
    , u.traffic_source
    , SUM(oi.sale_price) AS order_revenue
  FROM 
    `bigquery-public-data.thelook_ecommerce.orders` o
  JOIN 
    `bigquery-public-data.thelook_ecommerce.order_items` oi
      ON o.order_id = oi.order_id
  JOIN 
    `bigquery-public-data.thelook_ecommerce.users` u
      ON o.user_id = u.id
  WHERE true
    AND oi.status = 'Complete'
    AND oi.returned_at IS NULL
  GROUP BY 1,2,3,4,5
),

labeled_orders AS (
  SELECT
    order_id
    , user_id
    , order_month
    , traffic_source
    , order_revenue
    , CASE 
        WHEN order_date >= DATE '2022-01-15' THEN 'Post'
        ELSE 'Pre'
      END AS period
    , CASE
        WHEN order_revenue >= 100 THEN 'High_Value'
        ELSE 'Low_Value'
      END AS value_segment
  FROM base_orders
  --WHERE order_date BETWEEN DATE '2021-10-15' AND DATE '2022-04-15'
)

SELECT
  order_month
  , traffic_source
  , period
  , value_segment
  , COUNT(DISTINCT order_id) AS orders
  , SUM(order_revenue) AS total_revenue
  , AVG(order_revenue) AS avg_order_value
  , SAFE_DIVIDE(
      SUM(CASE WHEN value_segment = 'High_Value' THEN 1 ELSE 0 END),
      COUNT(*)
    ) AS pct_high_value_orders
FROM labeled_orders
GROUP BY
  order_month
  , traffic_source
  , period
  , value_segment
ORDER BY
  order_month
  , traffic_source
  , period
  , value_segment;
