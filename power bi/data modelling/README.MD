# Dimensional Data Model

This section documents the dimensional data model built for the Blue Canopy retail analytics project. The model organizes retail business processes into fact tables, describes the entities involved with dimensions, and connects the two using explicit keys and relationships. Its purpose is to make measures interpretable at a known grain and support consistent analysis across the project’s data marts.

## Dimensional model diagram

![Final dimensional data model for the Blue Canopy retail warehouse, showing the fact tables, descriptive dimensions, key-mapping bridge tables, and the promotion-to-product factless fact.](./final_dimensional_data_model.png)

*Figure 1. The final dimensional model. The central analytical processes include sales, inventory movement and snapshots, purchase-order fulfillment, store financials, customer experience and loyalty, gift-card events, campaign activity, and competitor performance. Descriptive dimensions such as date, product, store, customer, employee, supplier, account, campaign, and promotion provide context for those processes. Supporting key maps connect business identifiers to warehouse keys; the promotion-product association records coverage without a numeric transaction measure.*

The diagram is a relationship overview. It does not mean measures from different facts are automatically additive or directly comparable. Always consider each fact’s grain, date role, filter path, and business definition before combining results.

## Core concepts applied

### Fact tables and dimension tables

- **Facts** record business events or states, their dimensional keys, and measures. Examples include `fact_sales`, `fact_inventory_movements`, `fact_inventory_snapshots`, `fact_purchase_order_fulfillment`, and `fact_store_daily_financials`.
- **Dimensions** describe the people, places, products, dates, and other entities used to filter and group facts. Examples include `dim_date`, `dim_product`, `dim_store`, `dim_supplier`, `dim_customers`, `dim_employee`, and `dim_account`.
- The model has multiple business processes rather than one universal fact table. Facts can share descriptive dimensions while still having different definitions, coverage, and aggregation rules.

### Grain: what one fact row represents

Grain is defined before selecting measures and keys. It prevents double counting when facts are joined or summarized at different levels.

| Fact table | Grain in this project |
|---|---|
| `fact_sales` | One POS or e-commerce sales line; return attributes are associated with the sale line in the current build. |
| `fact_inventory_movements` | One stock movement event. |
| `fact_inventory_snapshots` | One store × product × snapshot date. |
| `fact_purchase_order_fulfillment` | One product line per purchase order; receipt batches are aggregated to the PO-product line. |
| `fact_store_daily_financials` | One store × financial date. |
| `fact_gl_transactions` | One general-ledger journal-entry line. |
| `fact_customer_experience` | One service interaction or feedback event. |
| `fact_customer_loyalty` | One loyalty transaction. |
| `fact_gift_card_transactions` | One gift-card event, such as issue, top-up, redeem, refund, expiry, or adjustment. |
| `fact_campaign` | One campaign record. |
| `fact_marketing` | One promotion record in the current Gold build. |
| `fact_competitor_qtrly_performance` | One competitor performance record at the stored quarterly geography/competitor grain. |
| `factless_fact_marketing` | One promotion × product association. |

Inventory movements are event flows; inventory snapshots are point-in-time states. Summing snapshot balances across dates does not produce movement volume. Likewise, sales lines, daily financial totals, and journal-entry lines are separate grains and must not be joined and summed as though each row represented the same event.

### Bridge tables and key mapping

The model uses supporting maps such as `product_bridge`, `dim_store_bridge`, `dim_supplier_bridge`, `employee_bridge`, and `bridge_counties`. They associate source business identifiers (for example, `product_id`, `store_id`, or `employee_id`) with the keys used by the warehouse facts and dimensions.

These project tables are primarily **key-mapping bridges**, not automatically many-to-many relationship tables. Their intended mapping is one row per business identifier. Check uniqueness and relationship cardinality before loading; a duplicate key on the one-side of a Power BI relationship can cause refresh failures or ambiguous filtering.

### Type 2 slowly changing dimensions

Silver source histories for entities such as products, stores, suppliers, customers, and employees include effective-date attributes such as `valid_from` and `valid_to`. Type 2 slowly changing dimension (SCD) history preserves successive versions of an entity when tracked attributes change, so the history can represent what was valid during different periods.

The Gold implementation does not currently preserve complete Type 2 versions in every reporting dimension. In particular, the current Gold builds for `dim_product`, `dim_store`, `dim_supplier`, and `dim_employee` select the latest row per business identifier. These dimensions support current-version reporting, but not full “as-was” historical reporting for those attributes. To support as-was analysis, facts must resolve to the dimension version effective on the fact date and retain that version’s surrogate key.

### Role-playing dimensions

- **Date roles:** `dim_date` relates to several business dates, including sale, return, order, receipt, movement, snapshot, financial, campaign, and promotion dates. One relationship can be active by default while other date roles are inactive. A visual filtered by the active date role does not automatically mean every other date field is filtered the same way; use a role-appropriate measure or a separate role-specific date dimension when simultaneous independent date filtering is needed.
- **Employee role:** Employee attributes support workforce reporting, while the employee/cashier key path connects POS sales to the cashier who handled the sale. This is an employee dimension playing the cashier role in the sales process. E-commerce has no cashier, so its zero cashier key represents not applicable/unknown rather than a real employee.

### Factless facts

`factless_fact_marketing` records promotion-product membership without a numeric sales or spend measure. It supports coverage questions such as which products were assigned to a promotion or how many products were on promotion. It does not, on its own, measure promotion lift, incremental revenue, or causality.

### Junk dimensions

Junk dimensions group related low-cardinality descriptors that are useful for analysis but do not need separate dimension tables. Examples in this model include `dim_sales_junk`, `customer_exp_junk`, and `customer_loyalty_junk`, which hold combinations of sales, customer-experience, or loyalty classifications.

### Natural keys, surrogate keys, and unknown values

Natural/business keys identify source entities; surrogate/warehouse keys provide model-facing identifiers for relationships. The bridge tables map between these key spaces. Do not treat keys as additive measures. Sentinel values such as `0` or `-1` should be interpreted as unknown or not applicable where the pipeline defines them that way, not as actual business entities.

## Modelling and interpretation guardrails

- Aggregate each fact according to its declared grain before relating it to another process.
- Use conformed dimensions for shared filtering, but do not assume two facts have the same business meaning or data coverage.
- Check one-side uniqueness, relationship direction, and active/inactive date roles in the semantic model.
- Do not sum periodic snapshot balances over time as transaction flows.
- Do not infer promotion ROI from promotion-product coverage or campaign spend.
- Sales and finance revenue remain unreconciled: an earlier same-store, same-period check found `fact_sales[net_sales]` about 80% above the corresponding `fact_store_daily_financials[sales_kes]`. Treat them as separate sources until investigated and reconciled.
