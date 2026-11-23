-- One schema per layer. Everything in sql/00_setup is safe to re-run.
CREATE SCHEMA IF NOT EXISTS raw;      -- rows exactly as delivered, one batch per file
CREATE SCHEMA IF NOT EXISTS staging;  -- typed and cleaned rows of the batch being processed
CREATE SCHEMA IF NOT EXISTS core;     -- dimensions with history and the sales fact
CREATE SCHEMA IF NOT EXISTS marts;    -- tables behind the analysis, rebuilt each run
CREATE SCHEMA IF NOT EXISTS ops;      -- run log, file manifest, check results
