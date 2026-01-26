{% docs __overview__ %}
# Airlines Argentina Data Stack

This project extracts flight data from the Aeropuertos Argentina API and models it with dbt to provide insights into flight delays, on-time performance, and operational metrics for Argentine airlines.

## How to navigate

- Raw tables land in `<env>_tap_airlines_arg` via Meltano.
- Staging models (`stg_*`) normalize raw data in dataset `stg`.
- Marts publish final models in dataset `marts` (prod/ci) or `SANDBOX_<DBT_USER>` in dev.
- Column documentation lives next to each model in YAML files.

## Data Model

### Staging Layer
- `stg_flights`: Normalized flight data with computed delays and flags
- `stg_airports`: Airport reference data derived from flight records
- `stg_airlines`: Airline reference data with performance metrics
- `stg_aircraft`: Aircraft registration and operational history

### Marts Layer
- `flights_performance`: Main fact table for flight-level analysis
- `airline_metrics`: Aggregated performance by airline
- `airport_operations`: Operational statistics by airport
- `delay_analysis`: Multi-grain delay patterns and trends

## How to run locally

1) Load env vars: `set -a; source ../.env; set +a`
2) Run extraction for your target: `meltano --environment=dev run tap-airlines-arg target-bigquery` (or `dev`/`ci`)
3) From `transform/`, install deps and build: `./scripts/setup-local.sh && source venv/bin/activate && dbt deps && dbt build --target dev`
4) Generate docs when needed: `dbt docs generate --target dev` and serve with `dbt docs serve`

## Tips

- Prefer `dbt build` over `dbt run` so tests stay enforced
- Set `DBT_USER` for sandboxed dev builds
- Add new models under `models/staging` or `models/production/marts` and keep their YAML docs beside them
- The raw data contains both arrivals and departures from the perspective of reporting airports
{% enddocs %}

{% docs __airlines-arg-data-stack__ %}
# Airlines Argentina Data Stack

End-to-end data pipeline for analyzing flight delays and airline operations in Argentina. Uses Meltano for extraction, dbt for transformation, and BigQuery as the warehouse.

## What to read next

- `README.md` for prerequisites and full quick start
- `models/staging/source_airlines.yml` for source table definitions
- `models/staging/*.yml` for staging column docs
- `models/production/marts/*.yml` for final model docs and tests

## Team workflow

- Keep `.env` in sync with your target project and datasets
- Build selectively during development: `dbt build --select <model> --target dev`
- Regenerate docs for reviewers after changes: `dbt docs generate --target dev`
- Use `ref()` for dependencies between models

## Key Concepts

### Flight Direction
- When `movement_type = 'A'`: flight is arriving AT `airport_code` FROM `origin_destination_code`
- When `movement_type = 'D'`: flight is departing FROM `airport_code` TO `origin_destination_code`

### Delay Calculation
- `delay_minutes = movement_actual_timestamp - scheduled_timestamp`
- `movement_actual_timestamp` uses block on/off when available (arrival: block on, departure: block off) and falls back to `actual_timestamp`
- Positive values indicate late arrivals/departures
- Negative values indicate early arrivals/departures
- Delay threshold: flights with `delay_minutes > 15` are considered delayed
- Average delay metrics exclude values outside `-180` to `600` minutes

### Time Dimensions
- `scheduled_hour`: Hour of day (0-23) for scheduled time
- `day_of_week`: Day of week (1=Sunday, 7=Saturday)
- `time_of_day`: Morning (5-12), Afternoon (12-18), Evening (18-22), Night (22-5)
{% enddocs %}
