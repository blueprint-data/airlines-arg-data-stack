{{ config(
    materialized='incremental',
    unique_key='flight_sk',
    tags=['marts', 'flights']
) }}

WITH last_extract AS (
    {% if is_incremental() %}
        SELECT COALESCE(MAX(_sdc_extracted_at), TIMESTAMP '1970-01-01 00:00:00+00') AS last_value
        FROM {{ this }}
    {% else %}
        SELECT TIMESTAMP '1970-01-01 00:00:00+00' AS last_value
    {% endif %}
),

flights AS (
    SELECT
        f.flight_sk,
        f.flight_id,
        f.flight_number,
        f.airline_code,
        f.airline_name,
        f.airport_code,
        f.origin_destination_code,
        f.origin_destination_city,
        f.movement_type,
        f.flight_direction,
        f.scheduled_timestamp,
        f.estimated_timestamp,
        f.actual_timestamp,
        f.delay_minutes,
        f.flight_date,
        f.scheduled_hour,
        f.day_of_week,
        f.month,
        f.year,
        f.flight_status,
        f.is_cancelled,
        f.is_delayed,
        f.delay_category,
        f.aircraft_type,
        f.aircraft_registration,
        f.gate,
        f.sector,
        f.terminal,
        f.baggage_belt,
        f.weather_temp,
        f.weather_description,
        f.fetched_at,
        f._sdc_extracted_at,
        f._sdc_received_at,
        f._sdc_batched_at
    FROM {{ ref('stg_flights') }} AS f
    WHERE f._sdc_extracted_at > (
        SELECT le.last_value
        FROM last_extract AS le
    )
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
    _sdc_extracted_at,
    _sdc_received_at,
    _sdc_batched_at,
    CURRENT_TIMESTAMP() AS dbt_updated_at
FROM with_flight_duration
