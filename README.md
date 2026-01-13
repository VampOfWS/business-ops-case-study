Executive Summary
This analysis evaluates revenue performance, customer mix, churn behavior, and the potential impact of a hypothetical free-shipping promotion using historical ecommerce data.

Key findings suggest revenue growth is driven by demand and traffic intent rather than basket expansion, with structurally flat AOV and low-frequency repeat behavior.

The free-shipping proxy analysis indicates promotions are more likely to shift purchase timing or mix than generate incremental value.



TASK A
Monthly revenue is calculated from completed, non-returned order items. Orders are counted as distinct order_ids with at least one completed item in the given month. AOV is defined as revenue divided by completed orders. Month-over-month growth compares total revenue to the previous calendar month.


---------- SQL CODE ----------
------------------------------
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
------------------------------
------------------------------



TASK B:
All definitions have the following rules:
- No assumptions outside of scope or unrelated.
- New is explicitly defined.
- No duplicates, meaning a user won’t be counted twice.

This definition treats customers as new only in their first purchase month. In a real product, we might refine this to account for reactivation after long inactivity windows.


---------- SQL CODE ----------
------------------------------
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
------------------------------
------------------------------




TASK C:
For each month, active customers are users with at least one completed, non-returned order in that month. A customer is considered churned if they were active in a given month but did not place any completed orders in the subsequent 90 days.

Be advised that this churn definition is forward-looking and assumes uniform purchase cycles. In real product, I would refine this by accounting for expected purchase frequency by segment or using survival analysis.

Example: a user churns in month M if:
	1. The user was active during month M
	2. The user does not have purchases 90 days after their last purchase on M.


---------- SQL CODE ----------
------------------------------
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
------------------------------
------------------------------




Churn is evaluated only for active users in a given month. A customer is considered churned if they were active in that month but did not place any completed orders in the subsequent 90 days. Months with no activity are not evaluated for churn.

LIMITATION
This churn definition assumes a uniform 90-day purchase cycle across all customers. It may overestimate churn for users with naturally longer repurchase intervals or seasonal behavior. Additionally, customers near the end of the dataset cannot be evaluated due to right-censoring.

Possible refinement:
In a real product setting, I would segment churn threshold by customer behavior (e.g., median repurchase time per cohort), or use survival analysis to model churn probability instead of a fixed window.


HEATMAP
---------- SQL CODE ----------
------------------------------
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
------------------------------
------------------------------


NOTE: This is a classic cohort retention heatmap for a non-subscription ecommerce.
Purchases are sparse, so retention appears in discrete long-tail months rather than continuous streaks.
Repeated retention rates indicate the same subset of users returning multiple times across time.


TASK D
Objective: 
Evaluate the potential impact of a hypothetical product change launched on 2022-01-15: a checkout banner promoting “Free shipping for orders over $100”, using historical data as a proxy.

Since the promotion is not actually present in the dataset, this analysis is directional rather than causal. The goal is to demonstrate how I would structure impact analysis given real-world data and instrumentation constraints.


Analytical Approach
To approximate the impact, I combine:
- A pre/post comparison around the launch date
- A proxy-based segmentation strategy to simulate feature exposure.

1. Base population.
I first restrict the analysis to economically meaningful transactions by including only:
- Completed orders
- Non-returned items

This ensures revenue and order value represent realized business outcomes rather than intent or transient activity.

---------- SQL CODE ----------
------------------------------

-- Base dataset: completed and non-returned orders
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
)

------------------------------
------------------------------

Note: Because the product change affects checkout behavior, and checkout completion happens at order level, using orders.created_at ensures temporal alignment with user intent and feature exposure.

traffic_source was extracted from the users table. This is because the acquisition channel is a user attribute, not an order attribute. Joining at the user level avoids duplicating or misattributing traffic_source across line items.

2. Proxy for feature exposure
Because the feature does not exist in the data, I simulate exposure using the following assumptions:
- Orders after 2022-01-15 are considered post-launch
- Orders with order_revenue >= $100 are treated as eligible for the promotion.

Using these proxies, I evaluate whether the following metrics change meaningfully after launch:
- Average Order Value (AOV)
- Monthly Revenue
- Share of high-value orders (> $100)

The underlying hypothesis is that the free-shipping threshold primarily influences basket size, rather than order frequency.


---------- SQL CODE ----------
------------------------------
SELECT 
  order_month
  , traffic_source
  , CASE WHEN order_date >= '2022-01-15' THEN 'Post' ELSE 'Pre' END AS period
  , AVG(order_revenue) AS avg_order_value
  , SUM(order_revenue) AS total_revenue
  , SUM(CASE WHEN order_revenue >= 100 THEN 1 ELSE 0 END) / COUNT(*) AS pct_high_value
FROM base_orders
WHERE order_date BETWEEN '2021-10-15' AND '2022-04-15'  -- 3mo pre/post, HOWEVER, this range
                                                        -- should be variable for a full analysis
GROUP BY 1,2,3
------------------------------
------------------------------

Note: In the order_date filter, a 3-month window balances statistical power with recency, though I'd also validate stability by comparing to the same periods in 2021 or even the last 3 years if data is available.

3. Counterfactual logic

In the absence of a true experiment, I treat orders below $100 as a quasi-control group under the assumption that they are less directly affected by the promotion.

Comparing pre/post trends between >$100 and < $100 orders approximates a difference-in-differences style comparison, helping to distinguish promotion-driven behavior from broader demand trends or seasonality.

While this DOES NOT establish causality, it strengthens directional inference relative to a simple pre/post comparison.

Additionally, as a refinement, I'd analyze repeat customers separately to isolate behavioral change from customer mix shift.



4. Segmentation Strategy
To identify heterogeneous effects, I segment results by traffic_source, under the assumption that:
- High-intent channels (between search, organic, display, email, Facebook) are more responsive to checkout incentives.
- Lower-intent channels may show weaker or no response.

This segmentation helps distinguish overall lift from channel-specific behavior changes and supports more targeted product decisions.


KEY ASSUMPTIONS
- The free shipping banner primarily influences order value, not traffic volume.
- Orders >= 100 are a reasonable (but imperfect) proxy for promotion exposure.
- No major pricing, merchandising, or UX changes occurred concurrently
- Customer behavior is otherwise stable across the pro/post window

These assumptions are necessary due to the absence of experimental instrumentation.


LIMITATIONS
- This analysis does not establish causality
- Customers are not randomly assigned to treatment/control.
- Seasonality and long-term trends are not explicitly controlled.
- Shipping costs and contribution margins are not observed

As a result, findings should be interpreted as directional signals, not true uplift estimates. It is also important to highlight that I'd calculate standard errors and test whether pre/post differences exceed expected variance, though without randomization, these are descriptive, not inferential.


WHAT I'D NEED TO DO THIS PROPERLY

In a real product environment, I would require:
- Experiment assignment (A/B test or feature flag)
- Explicit shipping fee fields
- User-level exposure logs
- Margin data (to evaluate profit, not just revenue)
- Time-based controls for seasonality (evaluate the same time period from previous years and establish a rolling baseline to assess trend stability)

With these, I would estimate causal lift using an experiment or quasi-experimental design.

I would also monitor order frequency and customer retention as guardrails. If AOV rises but repeat purchase drops, the promotion may be training one-time behavior.

Lastly, statistical testing would be used to assess whether observed differences exceed expected variance, though results remain descriptive.


INTERPRETATION FRAMEWORK
- If AOV and the share of >= $100 orders increase post-launch without a proportional drop in order volume, this suggests true basket expansion
- If revenue remains flat while AOV increases, this likely indicates order cannibalization (a shift in the mix, making shares or <= $100 increase in proportion).
- If effects are concentrated in high-intent traffic sources, this supports targeted checkout incentives rather than site-wide promotions.
                               


FULL CODE USED FOR SLIDESHOW
---------- SQL CODE ----------
------------------------------
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
------------------------------
------------------------------




-- USE OF AI --
Purpose of AI Usage

I used AI tools as analysis accelerators and critical reviewers, not as sources of truth. The goal was to pressure-test logic, identify blind spots, and improve executive clarity — while retaining full ownership of SQL logic, metric definitions, and conclusions.

Where AI Was Used
- Narrative validation:
I used LLMs to assess whether the story and conclusions were understandable without prior context and whether insights were framed at an executive level.

- Analytical gap detection:
I asked AI to identify missing comparisons, alternative hypotheses, or weak assumptions (e.g., mix shift vs. behavioral change, pre/post bias).

- Communication refinement:
I used AI to tighten language, reduce ambiguity, and ensure slides focused on business implications rather than descriptive reporting.

Example Prompts
“Do these conclusions logically follow from the data, or am I over-interpreting?”
“What questions would a skeptical PM or GM ask after seeing this slide?”
“Narrate this analysis back to me as if you were a VP seeing it for the first time.”

Validation and Safeguards
- All SQL was written, executed, and validated manually. AI did not generate or modify production queries without verification against schema definitions and dataset conventions.
- All conclusions were checked against actual outputs. If AI suggestions conflicted with observed trends, the data took precedence.
- AI feedback was treated as advisory, not authoritative. Final decisions on metric definitions, scope, and interpretation were mine.

Outcome

Using multiple AI tools helped surface blind spots faster and improve clarity, but did not change the underlying findings. The final deliverables reflect my analytical judgment, with AI acting as a structured reviewer rather than a decision-maker.