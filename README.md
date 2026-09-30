# Azure Supply Chain Analytics Platform

End-to-end cloud ETL pipeline on Azure: ingests raw supply chain data, models it into a star schema, and visualizes it through an interactive Power BI dashboard.

## Overview

This project builds a cloud-native data analytics pipeline using the DataCo Smart Supply Chain dataset (180,519 order-item records). Raw CSV data is ingested via Azure Blob Storage, orchestrated through an Azure Data Factory ETL pipeline, transformed into a star schema in Azure SQL Database, validated for data quality, and visualized through a Power BI dashboard with custom DAX measures.

## Architecture

**Flow:** Raw CSV → Azure Blob Storage → Azure Data Factory (Copy activity) → Azure SQL staging table → SQL transform layer → star schema (5 dimensions + 1 fact table) → Power BI dashboard

## Tech stack

- **Azure Blob Storage** — raw data landing zone
- **Azure Data Factory** — pipeline orchestration (Copy activity, scheduled trigger)
- **Azure SQL Database** (Serverless tier) — staging and modeled data storage
- **T-SQL** — schema design, transform logic, data validation
- **Power BI Desktop** — dashboard and DAX measures

## Data model

A star schema with one fact table and five dimension tables:

| Table | Row count | Description |
|---|---|---|
| fact_orders | 180,519 | One row per order line item |
| dim_customer | 20,652 | Unique customers |
| dim_product | 118 | Product catalog |
| dim_geography | 3,772 | Unique order locations |
| dim_shipping | 12 | Shipping mode x delivery status combinations |
| dim_date | 1,133 | Unique calendar dates (shared by order date and shipping date) |

dim_date is a role-playing dimension — fact_orders holds two foreign keys into it (Order_Date_Id and Shipping_Date_Id), avoiding a duplicate date table.

## Pipeline

The Data Factory pipeline (Copy_CSV_to_Staging) copies the raw CSV from Blob into a SQL staging table, using explicit column mapping to handle source column names containing spaces and parentheses. A daily schedule trigger was built and tested (fired manually, confirmed successful), then stopped to avoid unnecessary reprocessing of a static demo dataset.

Full pipeline definition: adf/pipeline_definition.json

## Data quality

A dedicated staging_rejects table and sp_ValidateStagingData stored procedure check for missing keys, invalid quantities, and logically impossible dates (e.g. shipping date before order date). All checks passed clean on this dataset — see sql/03_validation.sql.

## Dashboard

Two report pages:
- Executive Overview — total sales, profit, orders, margin; sales by category and region; sales trend over time
- Shipping Performance — late delivery rate, average shipping days, delay by shipping mode and region

8 DAX measures, including a USERELATIONSHIP()-based measure that activates the inactive shipping-date relationship — see powerbi/dax_measures.md.

## GenAI query layer

A Python-based natural language query assistant (query_assistant.py) built with Azure AI Foundry (GPT-4.1-mini), allowing plain-English questions to be translated into SQL queries against the Azure SQL Database. Confirmed working end-to-end — see genai/.

## Key design decisions

- Star schema over a flat table — normalizes repeated customer/product/location data, making the model faster to query and easier for Power BI to build relationships on.
- Staging vs. clean separation — raw data lands untouched in staging_orders; sensitive fields (Customer_Email, Customer_Password) are deliberately excluded from the modeled dimension tables, never reaching the reporting layer.
- Caught and fixed a geography deduplication bug — an initial dim_geography load included latitude/longitude in the dedup key, producing 64,867 "unique" rows instead of the correct 3,772, since tiny coordinate differences fragmented otherwise-identical cities. Fixed by grouping on categorical fields only and using MIN() for a representative coordinate.
- Idempotent transform logic — dimension and fact inserts use NOT EXISTS guards, making the transform script safe to re-run without creating duplicates.
- Trigger built, tested, then stopped — proved the scheduling mechanism works via a manual trigger run, then stopped it since the source dataset is static; a production version with live data would leave it running or move to an event-based trigger.

## Repository structure

sql/
  01_schema.sql          -- table creation (staging + star schema)
  02_transform.sql       -- dimension and fact population
  03_validation.sql      -- data quality checks + stored procedure
powerbi/
  dax_measures.md        -- all DAX measures used in the dashboard
adf/
  pipeline_definition.json  -- exported ADF pipeline definition
genai/
  query_assistant.py     -- natural language query layer (Azure AI Foundry)

## Future enhancements

- Event-based trigger for real (non-static) incoming data
- Truncate-and-reload or merge/upsert pattern for idempotent pipeline reruns
- Expand the GenAI query layer with conversational follow-up support