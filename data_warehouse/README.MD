# Blue Canopy Data Warehouse

The data warehouse for the **Blue Canopy Business Intelligence Project**. It implements a medallion-style architecture in Microsoft SQL Server, transforming raw synthetic CSV datasets into a business-ready star schema consumed by the Power BI semantic model.

This directory contains the SQL Server DDL, load procedures, and transformation logic that move data from **Bronze → Silver → Gold**, along with the architecture and lineage diagrams used to document the flow.

---

## Architecture

![High-Level Architecture](high_level_architecture.svg)

The warehouse is organized into three layered schemas inside a single SQL Server database (`Blue_canopy`):

| Layer | Purpose | Schema | Data | Load pattern |
| --- | --- | --- | --- | --- |
| **Bronze** | Raw, source-shaped ingest | `bronze` | 34 tables ending in `_raw` | Full reload from CSV, no transformation |
| **Silver** | Cleaned, standardized, enriched | `silver` | 34 curated tables | One stored procedure, full reload |
| **Gold** | Business-ready star schema | `gold` | Conformed dimensions + facts | One script per object, full reload |

The full flow is:

```mermaid
flowchart LR
    A[Python data generators] --> B[Raw CSV datasets]
    B --> C[Bronze raw tables]
    C --> D[Silver cleaned tables]
    D --> E[Gold star schema]
    E --> F[Power BI semantic model]
