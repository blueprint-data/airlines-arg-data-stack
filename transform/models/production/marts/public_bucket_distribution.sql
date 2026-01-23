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
)

SELECT
    'cancelled' AS bucket,
    COUNTIF(is_cancelled) AS total_flights
FROM base

UNION ALL

SELECT
    'delay_over_45' AS bucket,
    COUNTIF(NOT is_cancelled AND delay_minutes > 45) AS total_flights
FROM base

UNION ALL

SELECT
    'delay_45_30' AS bucket,
    COUNTIF(NOT is_cancelled AND delay_minutes > 30 AND delay_minutes <= 45) AS total_flights
FROM base

UNION ALL

SELECT
    'delay_30_15' AS bucket,
    COUNTIF(NOT is_cancelled AND delay_minutes > 15 AND delay_minutes <= 30) AS total_flights
FROM base

UNION ALL

SELECT
    'delay_15_0' AS bucket,
    COUNTIF(NOT is_cancelled AND delay_minutes > 0 AND delay_minutes <= 15) AS total_flights
FROM base

UNION ALL

SELECT
    'on_time_or_early' AS bucket,
    COUNTIF(NOT is_cancelled AND delay_minutes <= 0) AS total_flights
FROM base
