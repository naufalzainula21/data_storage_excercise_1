# Step 1 – Requirements Gathering

**Exercise 1 – Data Storage | Olist Data Warehouse**

---

## Overview

Before designing any data warehouse, a data engineer must align with stakeholders on the exact analytical needs, data quality expectations, and reporting cadence. Below is a simulated requirements-gathering session with Olist's key stakeholders (Product Manager, Business Analyst, Head of Logistics, and Marketing Lead).

---

## Questions & Stakeholder Answers

---

### Question 1 – Core Analytics Objectives

**Q:** What are the primary business questions you need the data warehouse to answer on a day-to-day basis?

**Stakeholder Answer (Product Manager):**
> "We mainly want to track sales performance—how much revenue each seller generates, which product categories are top-selling, and how orders trend over time. We also need to monitor customer satisfaction scores because negative reviews directly impact seller rankings on our platform. Finally, delivery performance is critical; late deliveries drive refund requests and bad reviews."

**Implication for DW Design:**
- Requires a **sales transaction fact table** (order items + revenue measures).
- Requires a **review fact table** or review measures attached to order facts.
- Requires an **accumulating snapshot fact table** to track order lifecycle milestones (placed → approved → shipped → delivered).

---

### Question 2 – Reporting Granularity & Frequency

**Q:** At what level of granularity do you need to analyze sales data, and how frequently do you need reports refreshed?

**Stakeholder Answer (Business Analyst):**
> "We need daily dashboards for operations. For executive reporting, monthly summaries per product category and per seller are sufficient. For delivery KPIs, we need to track each individual order across its lifecycle. Payment analysis needs to go down to the individual payment transaction because customers sometimes split payments across multiple methods."

**Implication for DW Design:**
- **Transaction Fact Table** grain: one row per order item.
- **Transaction Fact Table** grain: one row per payment transaction.
- **Accumulating Snapshot** grain: one row per order (tracking all lifecycle dates).
- **Periodic Snapshot** grain: one row per seller per product category per month.
- Refresh cadence: daily ETL for transactions, monthly roll-up for periodic snapshots.

---

### Question 3 – Delivery Performance KPIs

**Q:** What specific metrics do you use to measure delivery performance, and what thresholds define a "late" delivery?

**Stakeholder Answer (Head of Logistics):**
> "We track four milestones for every order: (1) order approval time, (2) time from approval to carrier pickup, (3) time from carrier pickup to customer delivery, and (4) comparison against the estimated delivery date we show to the customer. An order is 'late' if `order_delivered_customer_date > order_estimated_delivery_date`. We also want to see the number of days early or late, broken down by seller state and customer state."

**Implication for DW Design:**
- **Accumulating Snapshot Fact Table** `fact_order_delivery` must store four date foreign keys (purchase, approval, carrier handoff, customer delivery, estimated delivery).
- Derived measures: `days_to_approve`, `days_to_ship`, `days_to_deliver`, `delivery_delay_days`, `is_on_time` flag.
- Geolocation dimension (seller state, customer state) required for regional analysis.

---

### Question 4 – Customer Satisfaction & Review Analysis

**Q:** How do you want to analyze customer reviews, and should reviews be tied to specific products, sellers, or both?

**Stakeholder Answer (Marketing Lead):**
> "We want to see average review scores by product category, by seller, and by delivery region. We also need to know whether reviews with written comments differ in score distribution from those without. Ideally, we can cluster customers by review patterns to identify churned or at-risk customer segments. We need the review score at the order level, and since one order can have multiple items from multiple sellers, we need to be able to attribute reviews down to the seller or product level."

**Implication for DW Design:**
- **Review Transaction Fact Table** or review measures on the order fact.
- `has_comment` flag derived from `review_comment_message IS NOT NULL`.
- Dimensions: `dim_customer`, `dim_seller`, `dim_product`, `dim_date` all connected to reviews.
- Bridge or degenerate dimension for `order_id` to link reviews to order items.

---

### Question 5 – Payment Analysis

**Q:** What payment-related insights do you need, and how should split payments (multiple payment methods per order) be handled?

**Stakeholder Answer (Business Analyst):**
> "We need to know the most popular payment methods, average installment count by product category, and total payment volume by method per month. Since a single order can be paid with multiple methods (e.g., credit card + voucher), we need each payment transaction as a separate record. We also want to flag high-installment orders (more than 6 installments) because those correlate with potential default risk."

**Implication for DW Design:**
- **Transaction Fact Table** `fact_order_payments` at grain: one row per payment transaction per order.
- `dim_payment_type` dimension.
- Derived flag: `is_high_installment` (installments > 6).
- This table must be separately joinable from the order items fact via `order_id` (degenerate dimension or conformed dimension).

---

### Question 6 – Seller Performance

**Q:** How do you measure seller performance, and should the data warehouse support seller-level scorecards?

**Stakeholder Answer (Product Manager):**
> "Yes. Each seller should have a monthly scorecard showing: total revenue, number of orders fulfilled, average review score, on-time delivery rate, and top-selling product categories. We want to be able to compare sellers within the same state and product category."

**Implication for DW Design:**
- `dim_seller` with state and city attributes.
- **Periodic Snapshot Fact Table** `fact_monthly_sales` rolled up by seller and product category monthly.
- On-time delivery rate derived from `fact_order_delivery`.
- Conformed `dim_seller` and `dim_product` shared across all fact tables.

---

### Question 7 – Historical Data & SCD Handling

**Q:** Do you need to track historical changes in seller or customer information (Slowly Changing Dimensions)?

**Stakeholder Answer (Business Analyst):**
> "For sellers, their city/state rarely changes so Type 1 SCD (overwrite) is fine. For customers, since data is anonymized, we primarily track by `customer_unique_id`, and Type 1 is also acceptable. We just need to make sure we don't create duplicate customer records for the same unique customer who makes multiple purchases."

**Implication for DW Design:**
- `dim_customer` uses `customer_unique_id` as the natural key with SCD Type 1.
- `dim_seller` uses `seller_id` as the natural key with SCD Type 1.
- `dim_product` uses `product_id` as the natural key with SCD Type 1.

---

## Summary of Analytical Requirements

| Business Need | Fact Table Type | Key Dimensions |
|---|---|---|
| Sales & Revenue Tracking | Transaction | Date, Customer, Seller, Product |
| Payment Method Analysis | Transaction | Date, Customer, Payment Type |
| Delivery Performance | Accumulating Snapshot | Customer, Seller, Date (×5) |
| Monthly Sales Scorecard | Periodic Snapshot | Month, Seller, Product Category |
| Customer Review Analysis | Transaction | Date, Customer, Seller, Product |

---
