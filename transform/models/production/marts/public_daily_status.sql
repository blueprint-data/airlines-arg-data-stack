{{ config(
    materialized='view',
    tags=['marts', 'public']
) }}

{% set lookback_days = var('public_lookback_days', 60) %}

WITH base AS (
    SELECT
        f.flight_date,
        f.airline_name,
        f.flight_number,
        f.airport_code AS origin_airport_code,
        f.origin_destination_code AS destination_airport_code,
        dest.country AS destination_country,
        f.delay_minutes,
        f.flight_status,
        f.is_cancelled,
        f.scheduled_timestamp AS scheduled_departure_time,
        f.movement_actual_timestamp AS actual_departure_time,
        COALESCE(dest.city, f.origin_destination_city) AS destination_city
    FROM {{ ref('flights_performance') }} AS f
    LEFT JOIN {{ ref('stg_airports') }} AS dest
        ON f.origin_destination_code = dest.airport_code
    WHERE
        f.flight_date >= DATE_SUB(CURRENT_DATE(), INTERVAL {{ lookback_days }} DAY)
        AND f.movement_type = 'D'
),

daily_metrics AS (
    SELECT
        flight_date,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN is_cancelled THEN 1 ELSE 0 END) AS cancelled_flights,
        SUM(CASE WHEN delay_minutes > 30 THEN 1 ELSE 0 END) AS delayed_over_30min,
        ROUND(
            AVG(
                CASE
                    WHEN
                        actual_departure_time IS NOT NULL
                        AND delay_minutes BETWEEN -180 AND 600
                        THEN delay_minutes
                END
            ),
            1
        ) AS avg_delay_minutes
    FROM base
    GROUP BY flight_date
),

daily_destinations AS (
    SELECT
        flight_date,
        destination_city,
        destination_country,
        COUNT(*) AS total_flights,
        ROW_NUMBER() OVER (
            PARTITION BY flight_date
            ORDER BY COUNT(*) DESC
        ) AS rank
    FROM base
    WHERE destination_city IS NOT NULL
    GROUP BY flight_date, destination_city, destination_country
),

daily_top_destination AS (
    SELECT
        flight_date,
        destination_city AS top_destination_city,
        destination_country AS top_destination_country
    FROM daily_destinations
    WHERE rank = 1
)

SELECT
    dm.flight_date,
    dm.total_flights,
    dm.cancelled_flights,
    dm.delayed_over_30min,
    dm.avg_delay_minutes,
    dtd.top_destination_city,
    dtd.top_destination_country,
    CURRENT_TIMESTAMP() AS dbt_updated_at
FROM daily_metrics AS dm
LEFT JOIN daily_top_destination AS dtd
    ON dm.flight_date = dtd.flight_date
