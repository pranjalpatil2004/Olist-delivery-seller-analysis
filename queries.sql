-- ============================================================
-- Olist E-commerce Delivery & Seller Analysis (MySQL 8.0)
-- ============================================================

-- 0) Setup
CREATE DATABASE olist;
USE olist;
SET GLOBAL local_infile = 1;

-- 1) Load data (change the path to your own folder; use / not \)
DROP TABLE IF EXISTS olist_orders_dataset;
CREATE TABLE olist_orders_dataset (
  order_id VARCHAR(50),
  customer_id VARCHAR(50),
  order_status VARCHAR(20),
  order_purchase_timestamp DATETIME,
  order_approved_at DATETIME,
  order_delivered_carrier_date DATETIME,
  order_delivered_customer_date DATETIME,
  order_estimated_delivery_date DATETIME
);
LOAD DATA LOCAL INFILE 'C:/Users/YOUR_NAME/Desktop/olist_dataset/olist_orders_dataset.csv'
INTO TABLE olist_orders_dataset
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(order_id, customer_id, order_status, @a, @b, @c, @d, @e)
SET order_purchase_timestamp = NULLIF(@a,''),
    order_approved_at = NULLIF(@b,''),
    order_delivered_carrier_date = NULLIF(@c,''),
    order_delivered_customer_date = NULLIF(@d,''),
    order_estimated_delivery_date = NULLIF(@e,'');

DROP TABLE IF EXISTS olist_order_items_dataset;
CREATE TABLE olist_order_items_dataset (
  order_id VARCHAR(50),
  order_item_id INT,
  product_id VARCHAR(50),
  seller_id VARCHAR(50),
  shipping_limit_date DATETIME,
  price DECIMAL(10,2),
  freight_value DECIMAL(10,2)
);
LOAD DATA LOCAL INFILE 'C:/Users/YOUR_NAME/Desktop/olist_dataset/olist_order_items_dataset.csv'
INTO TABLE olist_order_items_dataset
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

DROP TABLE IF EXISTS olist_customers_dataset;
CREATE TABLE olist_customers_dataset (
  customer_id VARCHAR(50),
  customer_unique_id VARCHAR(50),
  customer_zip_code_prefix VARCHAR(10),
  customer_city VARCHAR(100),
  customer_state VARCHAR(5)
);
LOAD DATA LOCAL INFILE 'C:/Users/YOUR_NAME/Desktop/olist_dataset/olist_customers_dataset.csv'
INTO TABLE olist_customers_dataset
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

DROP TABLE IF EXISTS olist_sellers_dataset;
CREATE TABLE olist_sellers_dataset (
  seller_id VARCHAR(50),
  seller_zip_code_prefix VARCHAR(10),
  seller_city VARCHAR(100),
  seller_state VARCHAR(5)
);
LOAD DATA LOCAL INFILE 'C:/Users/YOUR_NAME/Desktop/olist_dataset/olist_sellers_dataset.csv'
INTO TABLE olist_sellers_dataset
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

DROP TABLE IF EXISTS olist_order_reviews_dataset;
CREATE TABLE olist_order_reviews_dataset (
  review_id VARCHAR(50),
  order_id VARCHAR(50),
  review_score INT,
  review_comment_title TEXT,
  review_comment_message TEXT,
  review_creation_date DATETIME,
  review_answer_timestamp DATETIME
);
LOAD DATA LOCAL INFILE 'C:/Users/YOUR_NAME/Desktop/olist_dataset/olist_order_reviews_dataset.csv'
INTO TABLE olist_order_reviews_dataset
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

-- 2) Data quality checks
SELECT order_status, COUNT(*) AS total
FROM olist_orders_dataset
GROUP BY order_status
ORDER BY total DESC;

SELECT COUNT(*) AS total_rows, COUNT(DISTINCT order_id) AS unique_orders
FROM olist_orders_dataset;                                   -- no duplicates

SELECT COUNT(*) AS delivered_but_no_date
FROM olist_orders_dataset
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NULL;                 -- 8 (excluded)

SELECT COUNT(*) AS wrong_dates
FROM olist_orders_dataset
WHERE order_delivered_customer_date < order_purchase_timestamp;  -- 0

-- 3) Overall late delivery KPI
SELECT
  COUNT(*) AS delivered_orders,
  SUM(order_delivered_customer_date > order_estimated_delivery_date) AS late_orders,
  ROUND(100 * SUM(order_delivered_customer_date > order_estimated_delivery_date) / COUNT(*), 2) AS late_pct
FROM olist_orders_dataset
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL;             -- 96470, 7826, 8.11

-- 4) Analysis table: one row per delivered order
DROP TABLE IF EXISTS order_delivery;
CREATE TABLE order_delivery AS
SELECT
  o.order_id,
  c.customer_state,
  c.customer_city,
  o.order_purchase_timestamp,
  o.order_delivered_customer_date,
  o.order_estimated_delivery_date,
  DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp) AS delivery_days,
  DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date) AS days_vs_estimate,
  CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
       THEN 'Late' ELSE 'On Time' END AS delivery_status,
  r.review_score
FROM olist_orders_dataset o
JOIN olist_customers_dataset c
  ON o.customer_id = c.customer_id
LEFT JOIN (
  -- some orders have more than one review; average per order to avoid duplicate rows
  SELECT order_id, ROUND(AVG(review_score), 2) AS review_score
  FROM olist_order_reviews_dataset
  GROUP BY order_id
) r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL;

SELECT COUNT(*) FROM order_delivery;                         -- 96470

-- 5) Analysis table: one row per seller
DROP TABLE IF EXISTS seller_performance;
CREATE TABLE seller_performance AS
SELECT
  i.seller_id,
  s.seller_state,
  s.seller_city,
  COUNT(DISTINCT i.order_id) AS total_orders,
  ROUND(SUM(i.price), 2) AS revenue,
  ROUND(100 * COUNT(DISTINCT CASE WHEN d.delivery_status = 'Late' THEN i.order_id END)
        / COUNT(DISTINCT i.order_id), 2) AS late_pct,
  ROUND(AVG(d.review_score), 2) AS avg_review_score
FROM olist_order_items_dataset i
JOIN order_delivery d
  ON i.order_id = d.order_id
JOIN olist_sellers_dataset s
  ON i.seller_id = s.seller_id
GROUP BY i.seller_id, s.seller_state, s.seller_city;

-- 6) Insight queries
-- Q1: late delivery by customer state
SELECT
  customer_state,
  COUNT(*) AS total_orders,
  SUM(delivery_status = 'Late') AS late_orders,
  ROUND(100 * SUM(delivery_status = 'Late') / COUNT(*), 2) AS late_pct,
  ROUND(AVG(delivery_days), 1) AS avg_delivery_days
FROM order_delivery
GROUP BY customer_state
ORDER BY late_pct DESC;

-- Q2: effect of late delivery on review score
SELECT
  delivery_status,
  COUNT(*) AS total_orders,
  ROUND(AVG(review_score), 2) AS avg_review_score
FROM order_delivery
WHERE review_score IS NOT NULL
GROUP BY delivery_status;

-- Q3: sellers with the highest late % (min 50 orders for a fair comparison)
SELECT seller_id, seller_state, total_orders, revenue, late_pct, avg_review_score
FROM seller_performance
WHERE total_orders >= 50
ORDER BY late_pct DESC
LIMIT 10;
