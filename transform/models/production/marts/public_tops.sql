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
        f.actual_timestamp AS actual_departure_time,
        COALESCE(dest.city, f.origin_destination_city) AS destination_city
    FROM {{ ref('flights_performance') }} AS f
    LEFT JOIN {{ ref('stg_airports') }} AS dest
        ON f.origin_destination_code = dest.airport_code
    WHERE
        f.flight_date >= DATE_SUB(CURRENT_DATE(), INTERVAL {{ lookback_days }} DAY)
        AND f.movement_type = 'D'
),

top_destinations AS (
    SELECT
        destination_city,
        destination_country,
        COUNT(*) AS total_flights,
        ROUND(
            AVG(CASE WHEN actual_departure_time IS NOT NULL THEN delay_minutes END),
            1
        ) AS avg_delay_minutes,
        ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS rank
    FROM base
    WHERE destination_city IS NOT NULL
    GROUP BY destination_city, destination_country
    QUALIFY rank <= 10
),

top_delays AS (
    SELECT
        flight_number,
        origin_airport_code,
        destination_airport_code,
        destination_city,
        destination_country,
        scheduled_departure_time,
        actual_departure_time,
        delay_minutes,
        ROW_NUMBER() OVER (ORDER BY delay_minutes DESC) AS rank
    FROM base
    WHERE
        actual_departure_time IS NOT NULL
        AND delay_minutes IS NOT NULL
    QUALIFY rank <= 10
),

top_early AS (
    SELECT
        flight_number,
        origin_airport_code,
        destination_airport_code,
        destination_city,
        destination_country,
        scheduled_departure_time,
        actual_departure_time,
        delay_minutes,
        ROW_NUMBER() OVER (ORDER BY delay_minutes ASC) AS rank
    FROM base
    WHERE
        actual_departure_time IS NOT NULL
        AND delay_minutes < 0
    QUALIFY rank <= 10
)

SELECT
    'top_destination' AS record_type,
    rank,
    destination_city,
    destination_country,
    total_flights,
    avg_delay_minutes,
    CAST(NULL AS STRING) AS flight_number,
    CAST(NULL AS STRING) AS origin_airport_code,
    CAST(NULL AS STRING) AS destination_airport_code,
    CAST(NULL AS TIMESTAMP) AS scheduled_departure_time,
    CAST(NULL AS TIMESTAMP) AS actual_departure_time,
    CAST(NULL AS FLOAT64) AS delay_minutes
FROM top_destinations

UNION ALL

SELECT
    'top_delay' AS record_type,
    rank,
    destination_city,
    destination_country,
    CAST(NULL AS INT64) AS total_flights,
    CAST(NULL AS FLOAT64) AS avg_delay_minutes,
    flight_number,
    origin_airport_code,
    destination_airport_code,
    scheduled_departure_time,
    actual_departure_time,
    delay_minutes
FROM top_delays

UNION ALL

SELECT
    'top_early' AS record_type,
    rank,
    destination_city,
    destination_country,
    CAST(NULL AS INT64) AS total_flights,
    CAST(NULL AS FLOAT64) AS avg_delay_minutes,
    flight_number,
    origin_airport_code,
    destination_airport_code,
    scheduled_departure_time,
    actual_departure_time,
    delay_minutes
FROM top_early
