# Building a Data Warehouse for Olist: A Complete Dimensional Modeling Walkthrough

*A Medium-style technical article — Exercise 1, Data Storage, Pacmann*

---

## Introduction

Imagine you are a Data Engineer at Olist — the largest department store in Brazilian e-commerce. Every day, thousands of orders flow through the platform, each touching multiple sellers, payment methods, delivery carriers, and customers who eventually leave a review. The raw operational data exists across nine interconnected source tables. But raw data alone doesn't answer the question a VP of Sales asks on a Monday morning: *"Why did our on-time delivery rate drop last month in São Paulo?"*

To answer that question — and hundreds like it — Olist needs a **data warehouse**: a purpose-built analytical environment designed for fast, consistent, and repeatable business insights.

This article walks through the complete process of designing Olist's data warehouse using the **Kimball dimensional modeling** methodology, from gathering requirements with stakeholders to producing a full schema with multiple fact table types.

---

## The Dataset

The Olist public dataset contains approximately 100,000 orders placed between 2016 and 2018. Its source schema consists of nine tables:

| Source Table | Description |
|---|---|
| `olist_orders_dataset` | Order header: status and all timestamp milestones |
| `olist_order_items_dataset` | One row per item: product, seller, price, freight |
| `olist_order_payments_dataset` | One row per payment method used per order |
| `olist_order_reviews_dataset` | Customer reviews tied to orders |
| `olist_products_dataset` | Product catalog with physical attributes |
| `olist_sellers_dataset` | Seller location data |
| `olist_customers_dataset` | Customer location data (anonymized) |
| `olist_geolocation_dataset` | Zip code to lat/lng mapping |
| `product_category_name_translation` | Portuguese → English category names |

Key structural complexities:
- **One-to-many orders to items**: a single order can contain items from different sellers.
- **One-to-many orders to payments**: a customer can split payment across multiple methods.
- **One review per order**, but reviews implicitly cover all items and sellers in that order.

These complexities make a single flat table approach unworkable for analytics. Dimensional modeling solves this elegantly.

---

## Phase 1 – Requirements Gathering

Before opening a SQL editor, a data engineer's job is to listen. I conducted a simulated requirements-gathering session with four Olist stakeholders: Product Manager, Business Analyst, Head of Logistics, and Marketing Lead.

### Key Questions Asked and What They Revealed

**1. What business questions do you need the DW to answer daily?**

The answer covered three themes: sales revenue tracking, customer satisfaction monitoring, and delivery performance. This immediately suggested **at least three distinct analytical subject areas** — each likely needing its own fact table.

**2. At what granularity do you need data?**

The stakeholders needed data at the order-item level (not just order level) for sales, at the individual payment transaction level, and at the per-order level for delivery tracking. Critically, they also needed monthly roll-ups for executive reporting. This answer directly maps to the **four fact table types** in our final design.

**3. What delivery KPIs matter most?**

The Head of Logistics defined four delivery milestones: approval time, time to carrier pickup, time to customer delivery, and comparison against estimated date. A delivery is "late" when `order_delivered_customer_date > order_estimated_delivery_date`. This clearly called for an **Accumulating Snapshot Fact Table** with five date dimension foreign keys.

**4. How should customer reviews be analyzed?**

The Marketing Lead wanted reviews tied to product categories, sellers, and delivery regions. Reviews needed a `has_comment` flag and connection to the customer dimension for churn analysis. This means reviews cannot be a simple column in the order fact — they need their own **Transaction Fact Table**.

**5. How do you handle split payments?**

Because one order can be paid with multiple methods (e.g., credit card for part, voucher for the rest), payment data requires its own **Transaction Fact Table** at payment-transaction grain.

**6. What does seller performance tracking look like?**

Monthly scorecards per seller showing revenue, order volume, average review score, and on-time delivery rate. This requirement drove the design of a **Periodic Snapshot Fact Table**.

### Summary of Requirements

From seven questions, five clear analytical needs emerged:

1. Sales & revenue analysis → Transaction fact (order items)
2. Payment method analysis → Transaction fact (payments)
3. Delivery performance → Accumulating snapshot (per order lifecycle)
4. Monthly seller scorecards → Periodic snapshot (monthly roll-up)
5. Customer review analysis → Transaction fact (reviews)

---

## Phase 2 – Dimensional Model Design

### Step 1: Select Business Processes

Kimball's first step is identifying **business processes** — the events the organization cares about measuring. For Olist, four processes were selected:

| Business Process | Why It Matters |
|---|---|
| Order Sales | Core revenue stream; product and seller performance |
| Order Payment | Payment methods drive financial risk and customer UX |
| Order Delivery Lifecycle | Late deliveries are the #1 driver of bad reviews |
| Customer Reviews | Leading indicator of seller rankings and churn |

### Step 2: Declare the Grain

The grain is the most important decision in dimensional modeling. It defines what one row in a fact table represents. Getting it wrong leads to double-counting or lost detail.

| Fact Table | Grain |
|---|---|
| `fact_order_items` | One row per order item |
| `fact_order_payments` | One row per payment transaction per order |
| `fact_order_delivery` | One row per order (updated at each milestone) |
| `fact_monthly_sales` | One row per seller per product category per month |
| `fact_order_reviews` | One row per review |

The most critical grain decision was choosing **order-item** (not order) for the sales fact table. This allows revenue attribution per seller and per product — impossible at order grain when multiple sellers fulfill the same order.

### Step 3: Identify the Dimensions

Six dimension tables were designed:

**`dim_date`** — The backbone of every fact table. Stores one row per calendar day with attributes like `day_name`, `month_name`, `quarter`, `year`, and `is_weekend`. This dimension **role-plays** in `fact_order_delivery`, where it appears five times under different aliases (purchase date, approval date, carrier date, delivered date, estimated delivery date).

**`dim_customer`** — Stores customer city, state, and zip code. Uses SCD Type 1 (overwrite). The key design decision: use `customer_unique_id` as the business natural key, since the same person generates a new `customer_id` with each order in the source system.

**`dim_seller`** — Stores seller location. Conformed across three fact tables: order items, delivery, and monthly snapshot. Enables cross-fact analysis like "does a seller's city affect their on-time delivery rate?"

**`dim_product`** — Includes physical attributes (weight, dimensions) alongside category name in both Portuguese and English. Used for freight cost analysis and category performance dashboards.

**`dim_payment_type`** — A small static lookup dimension with only a handful of distinct values (`credit_card`, `boleto`, `voucher`, `debit_card`). Pre-populated at schema creation.

**`dim_order_status`** — Another small static dimension. Pre-populated with all known statuses: `delivered`, `shipped`, `processing`, `canceled`, etc.

### Step 4: Design the Fact Tables

#### Transaction Fact Tables

Transaction fact tables capture **atomic business events**. Every time something happens — an item is sold, a payment is made, a review is submitted — one row is added. These tables grow continuously and are never updated.

**`fact_order_items`** is the central sales fact. Its measures are `price`, `freight_value`, and the derived `total_value`. Joined to five dimension tables, it supports queries like "show me total revenue by product category by seller state in Q3 2017."

**`fact_order_payments`** captures each payment sub-transaction. A single order may generate 2-3 rows here if the customer used multiple payment methods. The `is_high_installment` flag (installments > 6) is a derived boolean measure computed at load time.

**`fact_order_reviews`** stores review scores with `has_comment_title` and `has_comment_message` boolean flags. The `days_to_review` measure (review creation date minus order delivery date) reveals how long customers wait before reviewing — useful for designing nudge campaigns.

#### Accumulating Snapshot Fact Table

**`fact_order_delivery`** is the most architecturally interesting table in the schema. It holds **one row per order**, but that row is **updated multiple times** as the order moves through its lifecycle.

When an order is placed, a row is inserted with `purchase_date_key` populated and all other date keys set to `0` (a special "Not Yet Reached" placeholder in `dim_date`). As each milestone occurs:

- Olist approves the order → `approval_date_key` and `days_to_approve` are updated.
- Carrier picks up the order → `carrier_date_key` and `days_to_ship` are updated.
- Customer receives the order → `delivered_date_key`, `days_to_deliver`, `delivery_delay_days`, and `is_on_time` are updated.

This design allows a single query to answer: *"For orders placed in January 2018, what was the average time from purchase to delivery, and what percentage were on time?"* — without any complex joins back to the transaction table.

#### Periodic Snapshot Fact Table

**`fact_monthly_sales`** is populated by a monthly batch ETL job. At the end of each month, the job aggregates `fact_order_items` (for revenue, item counts) and joins in delivery and review data to produce a single summary row per seller per product category.

Unlike transaction facts, this table is **never updated for past periods**. Each month simply adds new rows. The result is a table that a BI tool can query in milliseconds for a seller's 12-month revenue trend — without scanning millions of order-item rows.

### Step 5: The Full ERD

The final schema has 11 tables: 6 dimension tables and 5 fact tables, connected in a classic star/snowflake pattern. The most notable structural feature is the **role-playing date dimension** — `dim_date` appears five times in `fact_order_delivery` under different column names, all pointing to the same physical table.

Key design rules reflected in the ERD:
- All fact tables use **integer surrogate keys** as primary keys.
- **Natural keys** from source systems (`order_id`, `review_id`) are stored as degenerate dimensions — not separate dimension tables — because they add no analytical attributes.
- All foreign keys to dimensions are **NOT NULL** (except `review_answer_date_key`, which is nullable if Olist never responded to a review).
- The `fact_monthly_sales.product_category` column is a denormalized string rather than an FK to `dim_product`, because the snapshot is at category level, not individual product level.

### Step 6: The Bus Matrix

The Bus Matrix is the master integration document for a data warehouse. It shows which dimensions are shared (conformed) across which fact tables.

| Dimension | Order Items | Payments | Delivery | Monthly Sales | Reviews |
|---|:---:|:---:|:---:|:---:|:---:|
| dim_date (purchase) | ✓ | ✓ | ✓ | ✓ | |
| dim_date (other milestones) | | | ✓ | | |
| dim_date (review dates) | | | | | ✓ |
| dim_customer | ✓ | ✓ | ✓ | | ✓ |
| dim_seller | ✓ | | ✓ | ✓ | |
| dim_product | ✓ | | | | |
| dim_payment_type | | ✓ | | | |
| dim_order_status | ✓ | | ✓ | | |

The Bus Matrix reveals that `dim_customer` and `dim_date` are the most conformed dimensions — they appear in 4 and 5 fact tables respectively. This means any cross-process analysis (e.g., "do customers who experienced late deliveries give lower review scores?") is possible by drilling across fact tables via these shared keys.

---

## Phase 3 – Design Decisions & Trade-offs

**Why use five fact tables instead of one?**

A single wide fact table would require either:
1. **Aggregating** payment data per order (losing installment-level detail), or
2. **Fanning out** order items to match payment rows (creating Cartesian explosions and false revenue sums).

Five purpose-built fact tables, each with a clear grain, avoid both problems.

**Why an Accumulating Snapshot for delivery?**

The delivery process is naturally stateful — an order has one lifecycle with defined milestones. A new transaction row per milestone event would make it hard to compute elapsed time between stages without complex self-joins. The accumulating snapshot puts all milestones in one row, making time-between-stages trivial to query.

**Why a Periodic Snapshot for monthly sales?**

The monthly snapshot is a performance optimization. Business users don't need millisecond-fresh data for trend reports. Pre-aggregating monthly reduces query time from minutes (full table scan) to milliseconds and enables consistent, reproducible month-end reporting.

**SCD Type 1 for all dimensions?**

The stakeholders confirmed that historical attribute changes (e.g., a seller moving cities) are not analytically important. SCD Type 1 (overwrite) simplifies ETL and avoids slowly growing dimension tables. If requirements change in the future (e.g., "show revenue by the seller's old location"), upgrading to SCD Type 2 with effective-date columns is a well-understood migration path.

---

## Conclusion

Designing a data warehouse is fundamentally a **translation exercise**: translating vague business questions into precise data models. The Kimball methodology provides a structured path:

1. **Requirements gathering** reveals what questions need answering.
2. **Business process selection** identifies what events to measure.
3. **Grain declaration** ensures analytical integrity.
4. **Dimension design** captures the "who, what, where, when, why" context.
5. **Fact table design** — using the right type for each process — captures the measurable outcomes.
6. **The Bus Matrix** ensures the whole warehouse is internally consistent.

The result for Olist is a warehouse that can answer — in seconds — questions that would take analysts hours to compute from raw source data. Sellers get monthly scorecards. The logistics team gets real-time delivery dashboards. The marketing team gets review sentiment inputs for their clustering models. The executive team gets trend reports that refresh monthly without manual SQL gymnastics.

That is the promise of a well-designed data warehouse: turning data chaos into decision clarity.

---

*Written as part of Exercise 1 – Data Storage, Sekolah Engineering, Pacmann.*

---
