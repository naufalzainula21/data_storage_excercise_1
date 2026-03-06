# Exercise 1 — Data Storage: Olist Data Warehouse Design

> **Course:** Data Engineering — Pacmann
> **Dataset:** [Olist Brazilian E-Commerce](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
> **Stack:** PostgreSQL · Dimensional Modeling (Kimball)

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Step 1 — Requirements Gathering](#2-step-1--requirements-gathering)
3. [Step 2 — Data Warehouse Model](#3-step-2--data-warehouse-model)
4. [Step 3 — Report](#4-step-3--report)
5. [Project Structure](#5-project-structure)
6. [Getting Started](#6-getting-started)

---

## 1. Project Overview

This project designs a **production-ready Data Warehouse** for **Olist**, the largest department store in Brazilian marketplaces. Olist connects small businesses to customers through various sales channels, generating large volumes of transactional data across sellers, products, payments, deliveries, and customer reviews.

The goal is to build a dimensional model that supports four core analytical objectives:

| Objective | Approach |
|---|---|
| Customer Satisfaction & Review Analysis | Transaction fact table for reviews |
| Customer Sentiment Clustering | Review scores + comment flags |
| Sales Prediction | Periodic snapshot (monthly roll-up) |
| Delivery Performance Optimization | Accumulating snapshot fact table |

The design follows the **Kimball dimensional modeling** methodology with a full star schema, multiple fact table types, and conformed dimensions.

---

## 2. Step 1 — Requirements Gathering

A simulated discovery session with Olist stakeholders (Product Manager, Business Analyst, Head of Logistics, Marketing Lead) produced 7 Q&A pairs that directly shaped the dimensional model.

Key findings:

| # | Question | Stakeholder Answer | DW Impact |
|---|---|---|---|
| 1 | Core analytics objectives? | Sales performance, review scores, delivery KPIs | 3 separate business processes |
| 2 | Reporting granularity? | Order-item level daily; monthly executive summaries | Multiple fact table grains |
| 3 | Delivery KPIs? | 4 milestones: purchase → approval → carrier → delivery vs. estimated | Accumulating snapshot with 5 date FKs |
| 4 | Review analysis? | Score by product, seller, region; comment flag; churn input | Separate review fact table |
| 5 | Split payments? | Multiple methods per order; installment behavior | Separate payment fact table |
| 6 | Seller scorecards? | Monthly revenue, order count, avg review, on-time rate | Periodic snapshot fact table |
| 7 | SCD requirements? | Type 1 for all dimensions (corrections only) | No historical versioning needed |

Full Q&A with detailed answers: [`step1_requirements_gathering.md`](step1_requirements_gathering.md)

---

## 3. Step 2 — Data Warehouse Model

### 3.1 Selected Business Processes

| # | Business Process | Source Tables |
|---|---|---|
| 1 | Order Sales | orders, order_items, products, sellers, customers |
| 2 | Order Payment | orders, order_payments, customers |
| 3 | Order Delivery Lifecycle | orders, customers, sellers |
| 4 | Customer Reviews | order_reviews, orders, order_items, customers |

### 3.2 Grain Declarations

| Fact Table | Type | Grain |
|---|---|---|
| `fact_order_items` | Transaction | One row per order item |
| `fact_order_payments` | Transaction | One row per payment transaction per order |
| `fact_order_delivery` | Accumulating Snapshot | One row per order (updated at each milestone) |
| `fact_monthly_sales` | Periodic Snapshot | One row per seller per product category per month |
| `fact_order_reviews` | Transaction | One row per review |

### 3.3 Dimension Tables

| Dimension | SCD Type | Key Attributes |
|---|---|---|
| `dim_date` | Static (no SCD) | date_key (YYYYMMDD), year, quarter, month, day_name, is_weekend |
| `dim_customer` | Type 1 | customer_unique_id (NK), city, state, zip_code_prefix |
| `dim_seller` | Type 1 | seller_id (NK), city, state, zip_code_prefix |
| `dim_product` | Type 1 | product_id (NK), category (PT + EN), physical dimensions |
| `dim_payment_type` | Static | payment_type (credit_card, boleto, voucher, debit_card) |
| `dim_order_status` | Static | order_status (delivered, shipped, canceled, …) |

### 3.4 Fact Tables

#### `fact_order_items` — Transaction Fact
Measures: `price`, `freight_value`, `total_value`
Dimensions: date, customer, seller, product, order_status

#### `fact_order_payments` — Transaction Fact
Measures: `payment_value`, `payment_installments`, `is_high_installment`
Dimensions: date, customer, payment_type

#### `fact_order_delivery` — Accumulating Snapshot Fact
Measures: `days_to_approve`, `days_to_ship`, `days_to_deliver`, `delivery_delay_days`, `is_on_time`
Date FKs: purchase, approval, carrier handoff, customer delivery, estimated delivery
`dim_date` is a **role-playing dimension** — it appears 5 times under different aliases.

#### `fact_monthly_sales` — Periodic Snapshot Fact
Measures: `total_orders`, `total_items_sold`, `total_revenue`, `total_freight`, `avg_review_score`, `on_time_delivery_rate`
Pre-aggregated monthly by ETL; historical rows never updated.

#### `fact_order_reviews` — Transaction Fact
Measures: `review_score`, `has_comment_title`, `has_comment_message`, `days_to_review`

### 3.5 ERD

The full ERD is available in two forms:
- **Interactive browser view:** [`erd_visualization.html`](erd_visualization.html) — open in any browser
- **Mermaid notation:** inside [`step2_dw_design.md`](step2_dw_design.md) (renders in VS Code, GitHub, or [mermaid.live](https://mermaid.live))

### 3.6 Bus Matrix

| Dimension | fact_order_items | fact_order_payments | fact_order_delivery | fact_monthly_sales | fact_order_reviews |
|---|:---:|:---:|:---:|:---:|:---:|
| dim_date (purchase) | ✓ | ✓ | ✓ | ✓ | |
| dim_date (milestones) | | | ✓ | | |
| dim_date (review dates) | | | | | ✓ |
| dim_customer | ✓ | ✓ | ✓ | | ✓ |
| dim_seller | ✓ | | ✓ | ✓ | |
| dim_product | ✓ | | | | |
| dim_payment_type | | ✓ | | | |
| dim_order_status | ✓ | | ✓ | | |

Full design with all table definitions, ERD, and bus matrix: [`step2_dw_design.md`](step2_dw_design.md)

---

## 4. Step 3 — Report

A Medium-style article summarizing the complete DW design process — from requirements to final schema — is available at: [`step3_report.md`](step3_report.md)

Topics covered:
- Olist dataset overview
- Requirements gathering walkthrough
- Business process selection rationale
- Grain declaration decisions
- Dimension design (SCD, role-playing, conformed)
- Three fact table types explained with use cases
- ERD and Bus Matrix interpretation
- Design trade-offs (single vs. multiple fact tables, SCD Type 1 rationale)

---

## 5. Project Structure

```
excercise_1/
├── README.md                          # This file
├── step1_requirements_gathering.md   # Step 1 — Stakeholder Q&A
├── step2_dw_design.md                 # Step 2 — Full dimensional model
├── step3_report.md                    # Step 3 — Medium-style report
├── schema_dwh.sql                     # PostgreSQL DDL for olist-dwh database
├── erd_visualization.html             # Interactive ERD viewer (open in browser)
└── soal/
    └── Exercise 1 - Data Storage - Pacmann.docx   # Original assignment
```

---

## 6. Getting Started

### Apply the DWH Schema

```bash
# Connect to your PostgreSQL instance and run:
psql -U postgres -d olist-dwh -f schema_dwh.sql
```

Or using the Docker setup from the assignment:

```bash
docker compose up -d
psql -h localhost -U postgres -d olist-dwh -f schema_dwh.sql
```

### View the ERD

Open `erd_visualization.html` in any browser (requires internet for Mermaid CDN).

Or paste the Mermaid code block from `step2_dw_design.md` into [mermaid.live](https://mermaid.live) for an instant rendered diagram.

### Clone the Repo

```bash
git clone https://github.com/naufalzainula21/data_storage_excercise_1.git
cd data_storage_excercise_1
```

---

*Exercise 1 — Data Storage | Pacmann Data Engineering Course*
