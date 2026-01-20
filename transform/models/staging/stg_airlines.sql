{{ config(
    materialized='view',
    tags=['staging']
) }}

WITH airline_names AS (
    SELECT DISTINCT
        airline_code,
        airline_name,
        ROW_NUMBER() OVER (
            PARTITION BY airline_code
            ORDER BY fetched_at DESC
        ) AS name_rank
    FROM {{ ref('stg_flights') }}
    WHERE airline_code IS NOT NULL
),

latest_airline_names AS (
    SELECT
        airline_code,
        airline_name
    FROM airline_names
    WHERE name_rank = 1
),

airline_stats AS (
    SELECT
        lan.airline_code,
        lan.airline_name,
        COUNT(*) AS total_flights,
        COUNT(DISTINCT f.flight_id) AS unique_flights,
        COUNT(DISTINCT f.airport_code) AS unique_airports,
        COUNT(DISTINCT CASE WHEN f.movement_type = 'A' THEN f.flight_id END) AS total_arrivals,
        COUNT(DISTINCT CASE WHEN f.movement_type = 'D' THEN f.flight_id END) AS total_departures,
        AVG(CASE WHEN f.actual_timestamp IS NOT NULL THEN f.delay_minutes END) AS avg_delay_minutes,
        SUM(CASE WHEN f.is_cancelled THEN 1 ELSE 0 END) AS total_cancelled,
        SUM(CASE WHEN f.is_delayed THEN 1 ELSE 0 END) AS total_delayed,
        SUM(CASE WHEN f.is_delayed THEN 0 ELSE 1 END) AS total_on_time,
        MIN(f.flight_date) AS first_seen_date,
        MAX(f.flight_date) AS last_seen_date,
        CURRENT_TIMESTAMP() AS dbt_updated_at
    FROM latest_airline_names AS lan
    LEFT JOIN {{ ref('stg_flights') }} AS f
        ON lan.airline_code = f.airline_code
    GROUP BY
        lan.airline_code,
        lan.airline_name
),

with_metrics AS (
    SELECT
        *,
        CASE
            WHEN total_flights > 0
                THEN (total_on_time * 100.0 / total_flights)
            ELSE 0
        END AS on_time_percentage,
        CASE
            WHEN total_flights > 0
                THEN (total_cancelled * 100.0 / total_flights)
            ELSE 0
        END AS cancellation_rate,
        CASE
            WHEN total_flights > 0
                THEN (total_delayed * 100.0 / total_flights)
            ELSE 0
        END AS delayed_percentage
    FROM airline_stats
)

SELECT
    airline_code,
    airline_name,
    total_flights,
    unique_flights,
    unique_airports,
    total_arrivals,
    total_departures,
    avg_delay_minutes,
    total_cancelled,
    total_delayed,
    total_on_time,
    on_time_percentage,
    cancellation_rate,
    delayed_percentage,
    first_seen_date,
    last_seen_date,
    dbt_updated_at
FROM with_metrics
ORDER BY total_flights DESC
