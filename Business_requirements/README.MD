# Business Requirements

## Business problem

Blue Canopy's retail information is distributed across operational data sources covering sales, customers, products, stores, inventory, procurement, finance, marketing, workforce, and customer experience. The project brief describes 29 source tables, but the data is not yet organized as one governed analytical foundation with consistent definitions, historical context, and shared business dimensions.

As a result, decision-makers lack a dependable way to answer cross-functional questions from the same analytical context. Sales, finance, inventory, customer, and marketing figures can be difficult to compare; raw transactional data requires preparation before it can be analyzed; and changes to products, stores, suppliers, or employees may not be available for historical analysis. The business is consequently less able to explain performance gaps, identify the operational drivers behind them, and act on those findings with confidence.

**In short: Blue Canopy needs a trusted, integrated, history-aware view of retail performance so its teams can move from disconnected operational data to consistent, explainable decisions.**

## Business impact

- Teams may spend time reconciling and preparing data instead of investigating business performance.
- Similar KPIs may be calculated from different sources or at different grains, creating inconsistent conclusions.
- Sales, margin, stock, fulfillment, customer, and campaign drivers are harder to analyze together.
- Without effective historical attribute tracking, analysis may describe an entity's current state rather than the state that applied when an event occurred.
- Leaders lack a consistent way to monitor performance against plans, thresholds, or operational benchmarks and prioritize exceptions.

## Business objective

Build an analytics-ready SQL Server warehouse and Power BI semantic model that brings the retail domains into a governed dimensional structure, preserves relevant historical context, and supports interactive, role-focused analysis. Users should be able to compare performance, investigate its drivers, and understand material data limitations before acting on a result.

## Required business capabilities

The solution is intended to support:

1. **Sales and profitability:** analyze sales, margin, discounts, returns, trends, and store/category performance against relevant plans or prior periods.
2. **Inventory and supply chain:** monitor on-hand stock, reorder and safety-stock exposure, purchase-order fulfillment, outstanding quantities, and supplier lead-time context.
3. **Store finance:** review store-level sales, costs, expenses, profit, and available target comparisons.
4. **Customer experience and loyalty:** understand feedback volume and ratings, issue categories, points activity, gift-card balances, and customer churn context.
5. **Marketing and competition:** track campaign budget and spend, promotion coverage, and competitor market context without inventing unsupported ROI or company market-share claims.
6. **Workforce:** review aggregate headcount, tenure, and retention-risk patterns to support further investigation without treating indicators as proof of cause.
7. **Data quality and interpretation:** expose data coverage, exceptions, benchmark assumptions, and known reconciliation gaps alongside the measures they affect.

## Proposed response

The project addresses the problem through a layered **Bronze → Silver → Gold** warehouse design and a dimensional semantic model:

- **Bronze** retains landed source data for traceability and reprocessing.
- **Silver** standardizes and enriches data and applies quality checks.
- **Gold** organizes business processes into facts and descriptive dimensions with explicit grains, keys, and relationships.
- **Power BI** presents the modeled data through interactive dashboards and reusable measures for business users.

The intended modeling techniques include conformed dimensions, surrogate and business keys, Type 2 history patterns, role-playing dates and employees, bridge/key-mapping tables, junk dimensions, and factless facts where they match the business process.

## Success criteria

The solution is successful when:

- Users can find the relevant business measure and understand its source, grain, and filter context.
- Shared dimensions provide consistent slicing across supported business processes.
- Historical reporting preserves prior attribute versions where the Gold model and fact keys support that behavior.
- Dashboards make material variances and exceptions actionable rather than showing unexplained totals.
- Data-quality issues, assumptions, and limitations are visible and are not presented as reconciled or verified facts.
- The Power BI project refreshes from its configured SQL Server sources and opens correctly in Power BI Desktop.

## Known limitation to communicate

The project has an unresolved sales-versus-finance discrepancy: a prior same-store, same-period comparison found `fact_sales[net_sales]` about 80% higher than the corresponding `fact_store_daily_financials[sales_kes]`. Until investigated and reconciled, these measures must remain clearly identified as separate sources and must not be presented as agreeing versions of the same total.

## Scope note

This is a batch-oriented SQL Server and Power BI analytics project. Real-time streaming, cloud deployment, automated production scheduling, and machine-learning attribution are outside the stated project scope. The dashboards should not imply that the platform provides those capabilities.
