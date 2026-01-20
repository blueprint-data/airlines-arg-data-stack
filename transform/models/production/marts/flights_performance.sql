{{ config(
    materialized='table',
    tags=['marts', 'flights']
) }}

WITH flights AS (
    SELECT
        flight_sk,
        flight_id,
        flight_number,
        airline_code,
        airline_name,
        airport_code,
        origin_destination_code,
        origin_destination_city,
        movement_type,
        flight_direction,
        scheduled_timestamp,
        estimated_timestamp,
        actual_timestamp,
        delay_minutes,
        flight_date,
        scheduled_hour,
        day_of_week,
        month,
        year,
        flight_status,
        is_cancelled,
        is_delayed,
        delay_category,
        aircraft_type,
        aircraft_registration,
        gate,
        sector,
        terminal,
        baggage_belt,
        weather_temp,
        weather_description,
        fetched_at
    FROM {{ ref('stg_flights') }}
),

time_of_day AS (
    SELECT
        *,
        CASE
            WHEN scheduled_hour >= 5 AND scheduled_hour < 12 THEN 'morning'
            WHEN scheduled_hour >= 12 AND scheduled_hour < 18 THEN 'afternoon'
            WHEN scheduled_hour >= 18 AND scheduled_hour < 22 THEN 'evening'
            ELSE 'night'
        END AS time_of_day
    FROM flights
),

with_flight_duration AS (
    SELECT
        *,
        CASE
            WHEN actual_timestamp IS NOT NULL
                THEN TIMESTAMP_DIFF(actual_timestamp, scheduled_timestamp, MINUTE)
        END AS flight_duration_minutes
    FROM time_of_day
)

SELECT
    flight_sk,
    flight_id,
    flight_number,
    airline_code,
    airline_name,
    airport_code,
    origin_destination_code,
    origin_destination_city,
    movement_type,
    flight_direction,
    scheduled_timestamp,
    estimated_timestamp,
    actual_timestamp,
    delay_minutes,
    flight_date,
    scheduled_hour,
    day_of_week,
    month,
    year,
    flight_status,
    is_cancelled,
    is_delayed,
    delay_category,
    aircraft_type,
    aircraft_registration,
    gate,
    sector,
    terminal,
    baggage_belt,
    weather_temp,
    weather_description,
    time_of_day,
    flight_duration_minutes,
    fetched_at,
    CURRENT_TIMESTAMP() AS dbt_updated_at
FROM with_flight_duration
