{{ config(
    materialized='view',
    tags=['marts', 'routes']
) }}

WITH base AS (
    SELECT *
    FROM {{ ref('routes_metrics_daily') }}
    WHERE flight_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY)
),

origin_airports AS (
    SELECT
        airport_code,
        airport_name,
        city,
        region,
        country
    FROM {{ ref('stg_airports') }}
),

destination_airports AS (
    SELECT
        airport_code,
        airport_name,
        city,
        region,
        country
    FROM {{ ref('stg_airports') }}
),

aggregated AS (
    SELECT
        base.origin_airport_code,
        origin.airport_name AS origin_airport_name,
        origin.city AS origin_city,
        origin.region AS origin_region,
        origin.country AS origin_country,
        base.destination_airport_code,
        destination.airport_name AS destination_airport_name,
        destination.city AS destination_city,
        destination.region AS destination_region,
        destination.country AS destination_country,
        base.airline_code,
        base.airline_name,
        MIN(base.flight_date) AS window_start_date,
        MAX(base.flight_date) AS window_end_date,
        SUM(base.total_flights) AS total_flights,
        SUM(base.total_completed_flights) AS total_completed_flights,
        SUM(base.total_cancelled_flights) AS total_cancelled_flights,
        SUM(base.total_delayed_flights) AS total_delayed_flights,
        SUM(base.total_on_time_flights) AS total_on_time_flights,
        SAFE_DIVIDE(
            SUM(base.avg_delay_minutes * base.total_completed_flights),
            SUM(base.total_completed_flights)
        ) AS avg_delay_minutes,
        CURRENT_TIMESTAMP() AS dbt_updated_at
    FROM base
    LEFT JOIN origin_airports AS origin
        ON base.origin_airport_code = origin.airport_code
    LEFT JOIN destination_airports AS destination
        ON base.destination_airport_code = destination.airport_code
    GROUP BY
        base.origin_airport_code,
        origin.airport_name,
        origin.city,
        origin.region,
        origin.country,
        base.destination_airport_code,
        destination.airport_name,
        destination.city,
        destination.region,
        destination.country,
        base.airline_code,
        base.airline_name
),

with_percentages AS (
    SELECT
        *,
        CASE
            WHEN total_flights > 0
                THEN SAFE_MULTIPLY(
                    SAFE_DIVIDE(total_on_time_flights, total_flights),
                    100.0
                )
            ELSE 0
        END AS on_time_percentage,
        CASE
            WHEN total_flights > 0
                THEN SAFE_MULTIPLY(
                    SAFE_DIVIDE(total_delayed_flights, total_flights),
                    100.0
                )
            ELSE 0
        END AS delayed_percentage,
        CASE
            WHEN total_flights > 0
                THEN SAFE_MULTIPLY(
                    SAFE_DIVIDE(total_cancelled_flights, total_flights),
                    100.0
                )
            ELSE 0
        END AS cancellation_rate
    FROM aggregated
)

SELECT
    origin_airport_code,
    origin_airport_name,
    origin_city,
    origin_region,
    origin_country,
    destination_airport_code,
    destination_airport_name,
    destination_city,
    destination_region,
    destination_country,
    airline_code,
    airline_name,
    window_start_date,
    window_end_date,
    total_flights,
    total_completed_flights,
    total_cancelled_flights,
    total_delayed_flights,
    total_on_time_flights,
    avg_delay_minutes,
    on_time_percentage,
    delayed_percentage,
    cancellation_rate,
    dbt_updated_at
FROM with_percentages
