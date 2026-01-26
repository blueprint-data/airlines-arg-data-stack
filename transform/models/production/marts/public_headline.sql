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
)

SELECT
    COUNT(*) AS total_flights,
    SUM(CASE WHEN is_cancelled THEN 1 ELSE 0 END) AS cancelled_flights,
    SUM(CASE WHEN delay_minutes > 30 THEN 1 ELSE 0 END) AS delayed_over_30min,
    SUM(CASE WHEN delay_minutes > 45 THEN 1 ELSE 0 END) AS delayed_over_45min,
    ROUND(
        AVG(CASE WHEN actual_departure_time IS NOT NULL THEN delay_minutes END),
        1
    ) AS avg_delay_minutes,
    {{ lookback_days }} AS lookback_days,
    CURRENT_TIMESTAMP() AS dbt_updated_at
FROM base
