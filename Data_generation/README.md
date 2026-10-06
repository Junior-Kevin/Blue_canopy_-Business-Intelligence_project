# Blue Canopy Data Generation

The synthetic data generation layer of the **Blue Canopy Business Intelligence Project**. This folder contains the Python scripts that produce the raw CSV datasets feeding the Bronze layer of the data warehouse, plus the generated CSVs themselves, organized by business domain.

All data is synthetic. It is created with seeded random generators to represent realistic retail operations in a Kenyan business context, including deliberate data quality imperfections that the warehouse is designed to clean.

---

## Folder structure

```
Data_generation/
│
├── Python_scripts/                   ← all generator scripts and orchestrators
│   ├── run_all_generators.py         ← master runner (executes generators in dependency order)
│   ├── <one .py per domain>          ← individual domain generators
│   ├── validation/                   ← data validation and profiling utilities
│   └── <config or utils>.py          ← shared helpers (faker seeding, file I/O)
│
└── csv_files/                        ← generated raw CSVs, grouped by domain
    ├── competitive_intelligence/     ← competitors, competitor stores, quarterly performance
    ├── crm/                          ← customer master
    ├── customer_loyalty/             ← loyalty transactions, gift cards, gift card transactions
    ├── customer_service/             ← service interactions, feedback
    ├── finance/                      ← store daily financials, general ledger
    ├── gis/                          ← counties, locations
    ├── hr/                           ← employee records
    ├── inventory/                    ← inventory movements, inventory snapshots
    ├── macroeconomic/                ← economic indicators by county and month
    ├── marketing/                    ← campaigns, promotions, promotion–product links
    ├── procurement/                  ← purchase orders, purchase order lines, goods receipts
    ├── products/                     ← product master (SCD2)
    ├── sales/                        ← POS transactions, POS lines, ecommerce orders,
    │                                     ecommerce order lines, returns
    ├── stores/                       ← store master (SCD2)
    └── suppliers/                    ← supplier master
```

---

## What this folder produces

Every CSV in `csv_files/` is a source dataset that maps to exactly one Bronze table in the warehouse. The naming convention is `<entity>.csv` → `bronze.<entity>_raw`.

| Domain | CSVs generated | Feeds Bronze table(s) |
| --- | --- | --- |
| **competitive_intelligence** | competitors, competitor_stores, competitor_quarterly | `competitors_raw`, `competitor_stores_raw`, `competitor_quarterly_raw` |
| **crm** | crm | `crm_raw` |
| **customer_loyalty** | loyalty_transactions, gift_cards, gift_card_transactions | `loyalty_transactions_raw`, `gift_cards_raw`, `gift_card_transactions_raw` |
| **customer_service** | service_interactions, feedback | `service_interactions_raw`, `feedback_raw` |
| **finance** | store_daily_financials, gl_transactions | `store_daily_financials_raw`, `gl_transactions_raw` |
| **gis** | gis_counties, gis_locations | `gis_counties_raw`, `gis_locations_raw` |
| **hr** | hr | `hr_raw` |
| **inventory** | inventory_movements, inventory_snapshots | `inventory_movements_raw`, `inventory_snapshots_raw` |
| **macroeconomic** | economic | `economic_raw` |
| **marketing** | campaigns, promotions, promotion_products | `campaigns_raw`, `promotions_raw`, `promotion_products_raw` |
| **procurement** | purchase_orders, purchase_order_lines, goods_receipts | `purchase_orders_raw`, `purchase_order_lines_raw`, `goods_receipts_raw` |
| **products** | products | `products_raw` |
| **sales** | pos_transactions, pos_line_items, ecommerce_orders, ecommerce_order_lines, returns | `pos_transactions_raw`, `pos_line_items_raw`, `ecommerce_orders_raw`, `ecommerce_order_lines_raw`, `returns_raw` |
| **stores** | stores | `stores_raw` |
| **suppliers** | suppliers | `suppliers_raw` |

---

## How to run the generators

### 1. Prepare the environment

Create a virtual environment and install the required packages:

```bash
cd Data_generation/Python_scripts
python -m venv .venv

# Windows
.venv\Scripts\activate

# macOS / Linux
source .venv/bin/activate

pip install pandas numpy faker
```

The exact list of dependencies may vary per script. If a generator imports something not installed above, `pip install <package>` as needed.

### 2. Run the master generator

The master runner executes all generators in dependency order — reference data (stores, products, suppliers) first, then transactions (POS, ecommerce, inventory) that reference them.

```bash
cd Data_generation/Python_scripts
python run_all_generators.py
```

This writes the CSVs to `Data_generation/csv_files/<domain>/`.

### 3. Run a single generator

If you only need one domain, run its script directly:

```bash
cd Data_generation/Python_scripts
python generate_<domain>.py
```

For example, to regenerate only sales data:

```bash
python generate_sales.py
```

Not all generators can run in isolation — some depend on outputs from earlier generators. Check the individual script for a "Depends on" docstring at the top of the file.

---

## Generator dependency order

Reference data must exist before transaction data that references it. The master runner enforces this order.

```
Tier 1 — Independent (no upstream dependencies)
  ├── stores
  ├── products
  ├── suppliers
  ├── gis
  └── macroeconomic

Tier 2 — Reference data that joins Tier 1
  ├── crm                    (references stores)
  ├── hr                     (references stores)
  ├── marketing              (references products)
  └── competitive_intelligence (references nothing internal)

Tier 3 — Operational transactions
  ├── sales                  (references crm, stores, products)
  ├── procurement            (references suppliers, products)
  └── inventory              (references stores, products, procurement)

Tier 4 — Post-transaction analytics
  ├── customer_loyalty       (references crm, sales)
  ├── customer_service       (references crm)
  └── finance                (references stores, sales, procurement)
```

Regenerating Tier 3 data without re-running Tier 1 and Tier 2 will produce orphan foreign keys. To keep the dataset consistent, always run `run_all_generators.py`.

---

## Design principles

All generators follow the same conventions so the resulting CSVs behave predictably in the warehouse.

### Deterministic output

Every script sets the same random seed at the top:

```python
random.seed(42)
np.random.seed(42)
Faker.seed(42)
```

This means re-running a generator produces the **same CSV** every time. Any randomness in the data is deterministic — reproducible across machines and runs. If you change the seed, you get a different (but still reproducible) dataset.

### Realistic business behavior

Generators produce data that reflects retail reality, not pure noise. Examples:

- **Sales velocity** varies by product popularity (Pareto distribution — top 20% of products drive ~80% of sales)
- **Seasonality** is applied to sales, inventory movements, and financials (Q4 spikes, January troughs, back-to-school lift)
- **Store coverage** varies — each store stocks 40–70% of the catalogue, not the full set
- **Replenishment** in inventory movements responds to depletion — stock does not go negative for well-behaved products
- **SCD2 versions** for products and stores reflect price changes, category migrations, and store format changes over time

### Deliberate data quality issues

The generators inject controlled imperfections so the Silver layer has real work to do. Common patterns:

- **`-DUP` suffix duplicates** — e.g. `PROD-0048-DUP` is a duplicate of `PROD-0048`
- **Date sentinels** — `2023-13-45` appears in date columns as an invalid value
- **Sign errors** — occasionally an outbound movement has a positive quantity, or vice versa
- **Null values** in columns the source system would normally populate (missing supplier, missing category)
- **Inconsistent casing and whitespace** — trailing spaces, mixed case in names
- **Orphan references** — some transactions reference stores or products that don't exist in the master tables

These issues are intentional. They are documented in the `data_warehouse/README.md` under "Data quality and known items".

---

## Validation utilities

The `Python_scripts/validation/` folder contains helpers to profile the generated CSVs before they are loaded into the warehouse. Typical checks include:

- Row count per file
- Null rate per column
- Distinct value count per column (to catch unexpected cardinality)
- Foreign key coverage (do all product_id values in sales exist in products?)
- Distribution summaries (percentiles, min/max) for numeric columns

Run these utilities after generating data if you want to verify the CSV shape before loading into Bronze.

---

## Output size and system requirements

The full generation run produces transaction- and snapshot-level files with millions of rows. Approximate sizes:

| Domain | Approximate rows | Notes |
| --- | --- | --- |
| sales | 4–6 million | POS lines + ecommerce lines + returns |
| inventory | 3–5 million movements + 8–15 million snapshots | Largest single-domain output |
| procurement | 1–2 million | PO lines dominate |
| crm | ~50,000 | Master data |
| products | ~5,000 (with SCD2 versions ~15,000) | Master data |
| stores | ~150 (with SCD2 versions) | Master data |
| All other domains | 10k–1M each | Varies |

**Before running the full generation**, check:

- At least **10 GB of free disk space** for the CSVs
- At least **8 GB of RAM** for pandas to load large chunks during generation
- Python 3.9 or later

Individual generators can be run selectively if you only need a subset of the data.

---

## Regenerating data

Two scenarios:

### Full regeneration
Delete the contents of `csv_files/` and run:

```bash
python run_all_generators.py
```

### Single-domain regeneration
Delete only the target folder and re-run its generator:

```bash
rm -rf csv_files/sales/
python generate_sales.py
```

Because seeds are fixed, regenerating `sales` alone produces the same file it did the first time. If you regenerate `products` (Tier 1) and then run `sales` (Tier 3), the sales data will still reference the same product IDs — the seeds ensure consistency across dependent domains.

---

## Tools and technologies

- **Python 3.9+** — scripting language for all generators
- **pandas** — data frame construction and CSV writing
- **NumPy** — vectorized random number generation
- **Faker** — realistic Kenyan names, addresses, phone numbers, and text fields
- **Seeded RNG** — deterministic output across machines and runs

---

## Status

This is part of an evolving portfolio project. All primary domains have working generators. Some generators have been refined after the initial pass to improve realism — notably the inventory generator, which now produces physically plausible stock movements with receipts preceding sales.

If a generator is being revised, both the script and its output CSV are kept in the repository so downstream code (Bronze loader, Silver transforms) can be tested against a stable snapshot.
