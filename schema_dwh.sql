-- ============================================================
-- Olist Data Warehouse – DDL Schema
-- Database: olist-dwh (PostgreSQL)
-- Exercise 1 – Data Storage | Pacmann
-- ============================================================

-- ============================================================
-- DIMENSION TABLES
-- ============================================================

-- 1. Date Dimension (role-playing dimension)
CREATE TABLE IF NOT EXISTS dim_date (
    date_key        INT PRIMARY KEY,          -- YYYYMMDD format, e.g. 20170901
    full_date       DATE        NOT NULL,
    day_of_week     SMALLINT    NOT NULL,      -- 1=Monday ... 7=Sunday
    day_name        VARCHAR(10) NOT NULL,
    day_of_month    SMALLINT    NOT NULL,
    week_of_year    SMALLINT    NOT NULL,
    month           SMALLINT    NOT NULL,
    month_name      VARCHAR(10) NOT NULL,
    quarter         SMALLINT    NOT NULL,
    year            SMALLINT    NOT NULL,
    is_weekend      BOOLEAN     NOT NULL DEFAULT FALSE,
    is_holiday      BOOLEAN     NOT NULL DEFAULT FALSE
);

COMMENT ON TABLE dim_date IS
    'Role-playing date dimension. Used multiple times in fact_order_delivery '
    'under aliases: purchase_date_key, approval_date_key, carrier_date_key, '
    'delivered_date_key, estimated_delivery_date_key.';

COMMENT ON COLUMN dim_date.date_key IS
    'Natural integer key in YYYYMMDD format. Special value 0 = "Not Yet Reached" '
    'for milestone dates that have not occurred.';


-- 2. Customer Dimension (SCD Type 1)
CREATE TABLE IF NOT EXISTS dim_customer (
    customer_key            SERIAL      PRIMARY KEY,
    customer_id             VARCHAR(50) NOT NULL,   -- order-scoped source ID
    customer_unique_id      VARCHAR(50) NOT NULL,   -- business key: unique per person
    customer_city           VARCHAR(100),
    customer_state          VARCHAR(10),
    customer_zip_code_prefix VARCHAR(10),
    -- ETL audit columns
    dw_created_at           TIMESTAMP   NOT NULL DEFAULT NOW(),
    dw_updated_at           TIMESTAMP   NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_dim_customer_unique_id
    ON dim_customer (customer_unique_id);

COMMENT ON TABLE dim_customer IS
    'SCD Type 1. customer_unique_id is the business natural key. '
    'customer_id is per-order and may differ for the same person across orders.';


-- 3. Seller Dimension (SCD Type 1)
CREATE TABLE IF NOT EXISTS dim_seller (
    seller_key              SERIAL      PRIMARY KEY,
    seller_id               VARCHAR(50) NOT NULL,   -- business natural key
    seller_city             VARCHAR(100),
    seller_state            VARCHAR(10),
    seller_zip_code_prefix  VARCHAR(10),
    -- ETL audit columns
    dw_created_at           TIMESTAMP   NOT NULL DEFAULT NOW(),
    dw_updated_at           TIMESTAMP   NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_dim_seller_seller_id
    ON dim_seller (seller_id);

COMMENT ON TABLE dim_seller IS
    'SCD Type 1. Conformed dimension shared by fact_order_items, '
    'fact_order_delivery, and fact_monthly_sales.';


-- 4. Product Dimension (SCD Type 1)
CREATE TABLE IF NOT EXISTS dim_product (
    product_key                     SERIAL       PRIMARY KEY,
    product_id                      VARCHAR(50)  NOT NULL,   -- business natural key
    product_category_name           VARCHAR(100),            -- Portuguese
    product_category_name_english   VARCHAR(100),            -- English (from translation)
    product_weight_g                FLOAT,
    product_length_cm               FLOAT,
    product_height_cm               FLOAT,
    product_width_cm                FLOAT,
    product_photos_qty              SMALLINT,
    product_name_length             INT,
    product_description_length      INT,
    -- ETL audit columns
    dw_created_at                   TIMESTAMP    NOT NULL DEFAULT NOW(),
    dw_updated_at                   TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_dim_product_product_id
    ON dim_product (product_id);

COMMENT ON TABLE dim_product IS
    'SCD Type 1. Physical product attributes included for freight cost analysis.';


-- 5. Payment Type Dimension
CREATE TABLE IF NOT EXISTS dim_payment_type (
    payment_type_key    SERIAL      PRIMARY KEY,
    payment_type        VARCHAR(50) NOT NULL UNIQUE  -- credit_card, boleto, voucher, debit_card
);

COMMENT ON TABLE dim_payment_type IS
    'Small static lookup dimension (<10 rows). '
    'Values: credit_card, boleto, voucher, debit_card, not_defined.';

-- Pre-populate known payment types
INSERT INTO dim_payment_type (payment_type) VALUES
    ('credit_card'),
    ('boleto'),
    ('voucher'),
    ('debit_card'),
    ('not_defined')
ON CONFLICT (payment_type) DO NOTHING;


-- 6. Order Status Dimension
CREATE TABLE IF NOT EXISTS dim_order_status (
    order_status_key    SERIAL      PRIMARY KEY,
    order_status        VARCHAR(50) NOT NULL UNIQUE
);

COMMENT ON TABLE dim_order_status IS
    'Small static lookup dimension. '
    'Values: created, approved, invoiced, processing, shipped, delivered, unavailable, canceled.';

-- Pre-populate known statuses
INSERT INTO dim_order_status (order_status) VALUES
    ('created'),
    ('approved'),
    ('invoiced'),
    ('processing'),
    ('shipped'),
    ('delivered'),
    ('unavailable'),
    ('canceled'),
    ('unknown')
ON CONFLICT (order_status) DO NOTHING;


-- ============================================================
-- FACT TABLES
-- ============================================================

-- -------------------------------------------------------
-- Fact 1: fact_order_items  (Transaction Fact Table)
-- Grain: one row per order item
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS fact_order_items (
    order_item_key      SERIAL          PRIMARY KEY,

    -- Degenerate dimensions (from source, no separate dim table)
    order_id            VARCHAR(50)     NOT NULL,
    order_item_id       SMALLINT        NOT NULL,

    -- Foreign keys to dimensions
    customer_key        INT             NOT NULL REFERENCES dim_customer(customer_key),
    seller_key          INT             NOT NULL REFERENCES dim_seller(seller_key),
    product_key         INT             NOT NULL REFERENCES dim_product(product_key),
    purchase_date_key   INT             NOT NULL REFERENCES dim_date(date_key),
    order_status_key    INT             NOT NULL REFERENCES dim_order_status(order_status_key),

    -- Measures
    price               NUMERIC(10,2)   NOT NULL DEFAULT 0,
    freight_value       NUMERIC(10,2)   NOT NULL DEFAULT 0,
    total_value         NUMERIC(10,2)   GENERATED ALWAYS AS (price + freight_value) STORED,

    -- ETL audit
    dw_created_at       TIMESTAMP       NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_foi_order_id         ON fact_order_items (order_id);
CREATE INDEX IF NOT EXISTS idx_foi_customer_key      ON fact_order_items (customer_key);
CREATE INDEX IF NOT EXISTS idx_foi_seller_key        ON fact_order_items (seller_key);
CREATE INDEX IF NOT EXISTS idx_foi_product_key       ON fact_order_items (product_key);
CREATE INDEX IF NOT EXISTS idx_foi_purchase_date_key ON fact_order_items (purchase_date_key);

COMMENT ON TABLE fact_order_items IS
    'Transaction Fact Table. Grain: one row per order item. '
    'Supports revenue, seller performance, and product category analysis.';


-- -------------------------------------------------------
-- Fact 2: fact_order_payments  (Transaction Fact Table)
-- Grain: one row per payment transaction per order
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS fact_order_payments (
    payment_key             SERIAL          PRIMARY KEY,

    -- Degenerate dimensions
    order_id                VARCHAR(50)     NOT NULL,
    payment_sequential      SMALLINT        NOT NULL,   -- sequence within order

    -- Foreign keys to dimensions
    customer_key            INT             NOT NULL REFERENCES dim_customer(customer_key),
    payment_type_key        INT             NOT NULL REFERENCES dim_payment_type(payment_type_key),
    purchase_date_key       INT             NOT NULL REFERENCES dim_date(date_key),

    -- Measures
    payment_installments    SMALLINT        NOT NULL DEFAULT 1,
    payment_value           NUMERIC(10,2)   NOT NULL DEFAULT 0,
    is_high_installment     BOOLEAN         GENERATED ALWAYS AS (payment_installments > 6) STORED,

    -- ETL audit
    dw_created_at           TIMESTAMP       NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_fop_order_id             ON fact_order_payments (order_id);
CREATE INDEX IF NOT EXISTS idx_fop_customer_key         ON fact_order_payments (customer_key);
CREATE INDEX IF NOT EXISTS idx_fop_payment_type_key     ON fact_order_payments (payment_type_key);
CREATE INDEX IF NOT EXISTS idx_fop_purchase_date_key    ON fact_order_payments (purchase_date_key);

COMMENT ON TABLE fact_order_payments IS
    'Transaction Fact Table. Grain: one row per payment transaction per order. '
    'Supports payment method analysis and installment behavior tracking.';


-- -------------------------------------------------------
-- Fact 3: fact_order_delivery  (Accumulating Snapshot Fact Table)
-- Grain: one row per order — updated as milestones are reached
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS fact_order_delivery (
    delivery_key                    SERIAL          PRIMARY KEY,

    -- Degenerate dimension
    order_id                        VARCHAR(50)     NOT NULL UNIQUE,  -- one row per order

    -- Foreign keys to dimensions
    customer_key                    INT             NOT NULL REFERENCES dim_customer(customer_key),
    seller_key                      INT             REFERENCES dim_seller(seller_key),   -- primary seller
    order_status_key                INT             NOT NULL REFERENCES dim_order_status(order_status_key),

    -- Role-playing date FKs (0 = "Not Yet Reached")
    purchase_date_key               INT             NOT NULL REFERENCES dim_date(date_key),
    approval_date_key               INT             NOT NULL REFERENCES dim_date(date_key) DEFAULT 0,
    carrier_date_key                INT             NOT NULL REFERENCES dim_date(date_key) DEFAULT 0,
    delivered_date_key              INT             NOT NULL REFERENCES dim_date(date_key) DEFAULT 0,
    estimated_delivery_date_key     INT             NOT NULL REFERENCES dim_date(date_key) DEFAULT 0,

    -- Measures (NULL = milestone not yet reached)
    days_to_approve                 FLOAT,
    days_to_ship                    FLOAT,
    days_to_deliver                 FLOAT,
    delivery_delay_days             FLOAT,   -- positive = late, negative = early
    is_on_time                      BOOLEAN,

    -- ETL audit
    dw_created_at                   TIMESTAMP       NOT NULL DEFAULT NOW(),
    dw_updated_at                   TIMESTAMP       NOT NULL DEFAULT NOW()   -- updated on each milestone
);

CREATE INDEX IF NOT EXISTS idx_fod_customer_key                 ON fact_order_delivery (customer_key);
CREATE INDEX IF NOT EXISTS idx_fod_seller_key                   ON fact_order_delivery (seller_key);
CREATE INDEX IF NOT EXISTS idx_fod_purchase_date_key            ON fact_order_delivery (purchase_date_key);
CREATE INDEX IF NOT EXISTS idx_fod_delivered_date_key           ON fact_order_delivery (delivered_date_key);

COMMENT ON TABLE fact_order_delivery IS
    'Accumulating Snapshot Fact Table. Grain: one row per order. '
    'Rows are inserted on order creation and updated as each delivery milestone is reached. '
    'Tracks: purchase, approval, carrier handoff, customer delivery, and estimated delivery. '
    'date_key=0 is reserved as "Not Yet Reached" in dim_date.';


-- -------------------------------------------------------
-- Fact 4: fact_monthly_sales  (Periodic Snapshot Fact Table)
-- Grain: one row per seller per product category per calendar month
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS fact_monthly_sales (
    monthly_sales_key       SERIAL          PRIMARY KEY,

    -- Foreign keys to dimensions
    snapshot_month_key      INT             NOT NULL REFERENCES dim_date(date_key),  -- first day of month
    seller_key              INT             NOT NULL REFERENCES dim_seller(seller_key),

    -- Denormalized category (aggregated at category level, not product level)
    product_category        VARCHAR(100)    NOT NULL,

    -- Measures
    total_orders            INT             NOT NULL DEFAULT 0,
    total_items_sold        INT             NOT NULL DEFAULT 0,
    total_revenue           NUMERIC(12,2)   NOT NULL DEFAULT 0,
    total_freight           NUMERIC(12,2)   NOT NULL DEFAULT 0,
    avg_review_score        FLOAT,
    on_time_delivery_rate   FLOAT,          -- 0.0 to 1.0
    total_reviews           INT             NOT NULL DEFAULT 0,

    -- ETL audit
    dw_created_at           TIMESTAMP       NOT NULL DEFAULT NOW(),

    -- Unique constraint: one row per seller+category+month
    UNIQUE (snapshot_month_key, seller_key, product_category)
);

CREATE INDEX IF NOT EXISTS idx_fms_snapshot_month_key  ON fact_monthly_sales (snapshot_month_key);
CREATE INDEX IF NOT EXISTS idx_fms_seller_key          ON fact_monthly_sales (seller_key);
CREATE INDEX IF NOT EXISTS idx_fms_product_category    ON fact_monthly_sales (product_category);

COMMENT ON TABLE fact_monthly_sales IS
    'Periodic Snapshot Fact Table. Grain: one row per seller per product category per month. '
    'Populated by monthly batch ETL job. Historical rows are NOT updated. '
    'Enables fast executive reporting without full transaction table scans.';


-- -------------------------------------------------------
-- Fact 5: fact_order_reviews  (Transaction Fact Table)
-- Grain: one row per review (one review per order)
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS fact_order_reviews (
    review_key                  SERIAL          PRIMARY KEY,

    -- Degenerate dimensions
    review_id                   VARCHAR(50)     NOT NULL,
    order_id                    VARCHAR(50)     NOT NULL,

    -- Foreign keys to dimensions
    customer_key                INT             NOT NULL REFERENCES dim_customer(customer_key),
    review_creation_date_key    INT             NOT NULL REFERENCES dim_date(date_key),
    review_answer_date_key      INT             REFERENCES dim_date(date_key),  -- nullable (may not be answered)

    -- Measures
    review_score                SMALLINT        NOT NULL CHECK (review_score BETWEEN 1 AND 5),
    has_comment_title           BOOLEAN         NOT NULL DEFAULT FALSE,
    has_comment_message         BOOLEAN         NOT NULL DEFAULT FALSE,
    days_to_review              FLOAT,          -- review_creation − order_delivered

    -- ETL audit
    dw_created_at               TIMESTAMP       NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_for_review_id   ON fact_order_reviews (review_id);
CREATE INDEX IF NOT EXISTS idx_for_order_id          ON fact_order_reviews (order_id);
CREATE INDEX IF NOT EXISTS idx_for_customer_key      ON fact_order_reviews (customer_key);
CREATE INDEX IF NOT EXISTS idx_for_creation_date_key ON fact_order_reviews (review_creation_date_key);

COMMENT ON TABLE fact_order_reviews IS
    'Transaction Fact Table. Grain: one row per review. '
    'Supports customer satisfaction KPIs, review score distribution, '
    'and input data for NLP sentiment clustering.';


-- ============================================================
-- SPECIAL DATE KEY: "Not Yet Reached" placeholder
-- Required by fact_order_delivery for unmet milestones
-- ============================================================
INSERT INTO dim_date (
    date_key, full_date, day_of_week, day_name, day_of_month,
    week_of_year, month, month_name, quarter, year, is_weekend, is_holiday
)
VALUES (0, '1900-01-01', 1, 'Monday', 1, 1, 1, 'January', 1, 1900, FALSE, FALSE)
ON CONFLICT (date_key) DO NOTHING;

COMMENT ON TABLE dim_date IS
    'date_key=0 is the "Not Yet Reached" placeholder used in fact_order_delivery '
    'for milestone date FKs that have not been populated yet.';
