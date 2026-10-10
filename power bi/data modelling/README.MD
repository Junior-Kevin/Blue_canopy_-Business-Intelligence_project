# Power BI

This section contains the Power BI reporting work for the Blue Canopy retail analytics project. It documents the semantic model and the six-page report, with a focus on business decisions, data context, and known limitations.

## Contents

The GitHub `power bi` section is organized into:

- **`data modelling/`** — dimensional-model documentation, concepts, and the model diagram.
- **`data visualization/`** — report design, dashboard documentation, and visualization work.
- **`README.MD`** — overview and navigation for this Power BI section.

See the [Data Modelling README](./data%20modelling/README.MD) for the model concepts and grain definitions.

The Power BI Desktop project in this working directory is provided as a Power BI Project (`.pbip`):

- [`retail_sales.pbip`](./retail_sales.pbip) — project entry point.
- [`retail_sales.SemanticModel/`](./retail_sales.SemanticModel/) — tabular model definition, relationships, Power Query expressions, and DAX measures.
- [`retail_sales.Report/`](./retail_sales.Report/) — report pages, visual definitions, and theme resources.
- [`POWER_BI_SIX_PAGE_BLUEPRINT.md`](./POWER_BI_SIX_PAGE_BLUEPRINT.md) — page layouts, design system, caveats, and a practical build sequence.

## Report pages

The report is organized around six data marts:

| Order | Page | Focus |
|---:|---|---|
| 1 | **Sales & Profitability** | Sales and margin performance against plan and prior-year context, with store and product-category drivers. |
| 2 | **Inventory & Supply Chain** | Snapshot stock risk, purchase-order fulfillment, outstanding quantities, and supplier lead-time context. |
| 3 | **Store Finance** | Finance-source sales, profit and expense performance, trends, and target comparisons. |
| 4 | **Customer Experience & Loyalty** | Customer satisfaction, feedback issues, loyalty activity, gift-card balances, and churn context. |
| 5 | **Marketing & Competition** | Campaign budget delivery, promotions, and competitor-only market context. |
| 6 | **Workforce & Retention** | Aggregate active headcount, tenure, and department-level retention-risk context. |

## Design approach

Pages use a consistent 16:9 canvas, a restrained palette, contextual KPI cards, an insight headline, decision-focused charts, and a footer for data coverage or caveats. Existing model measures are reused; the report does not imply unsupported targets, causal explanations, campaign ROI, or Blue Canopy market share.

The full layout and visualization guidance is in the [six-page blueprint](./POWER_BI_SIX_PAGE_BLUEPRINT.md).

## Open the project

1. Download or clone the repository, including the `.pbip`, report, and semantic-model folders.
2. Open `retail_sales.pbip` in Power BI Desktop.
3. Configure or confirm the data-source connection and credentials in the local Power BI environment.
4. Refresh the model and review any refresh errors before interpreting report values.
5. Save changes from Power BI Desktop so report and model definitions remain synchronized.

Power BI Desktop is required to fully validate report rendering and model behavior. A JSON parse or repository preview is not a substitute for opening and saving the project in Desktop.

## Data-quality and interpretation notes

- **Sales and finance revenue are not reconciled.** A same-store, same-period check found `fact_sales[net_sales]` about 80% higher than the corresponding `fact_store_daily_financials[sales_kes]`. Treat these as separate sources until the discrepancy is resolved.
- **Inventory lead-time comparisons have data exceptions.** Some purchase-order receipt dates precede the order date or are incomplete; invalid intervals are excluded from lead-time comparisons.
- **PO fulfillment uses an assumed benchmark.** The report uses 97% as a stated comparison benchmark, not as a value sourced from a formal target table.
- **The CSAT rating benchmark is assumed.** The current customer-experience target table contains resolution-time targets rather than verified rating targets, so 4.0 is an explicit assumption.
- **Loyalty, gift-card, and churn measures have different scopes.** Gift-card balances and customer churn are current-population measures and are not necessarily filtered by the loyalty transaction date.
- **Marketing attribution is not modeled as ROI.** Campaign spend is not proof of incremental sales or promotion lift. Competitor market-share data does not provide a Blue Canopy market-share denominator.
- **Workforce indicators are current-state summaries.** They should be interpreted in aggregate and not as individual assessments or dated trends.

Where coverage dates are displayed, use the measure or source table that actually defines that coverage. Do not infer a common data-as-of date across marts with different refresh schedules.

## Repository hygiene

The Power BI project `.gitignore` excludes local Desktop cache and settings files under `.pbi/`. Do not commit local credentials, connection secrets, or machine-specific settings. Keep required project definitions and report assets under version control, and verify the project opens in Power BI Desktop after pulling repository changes.
