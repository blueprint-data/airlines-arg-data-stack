{{ config(
    materialized='incremental',
    unique_key='flight_sk',
    tags=['staging']
) }}

WITH source_rows AS (
    SELECT src.*
    FROM {{ source('tap_airlines', 'aerolineas_all_flights') }} AS src
    {% if is_incremental() %}
        WHERE src._sdc_extracted_at > (
            SELECT MAX(t._sdc_extracted_at)
            FROM {{ this }} AS t
        )
    {% endif %}
),

parsed_json AS (
    SELECT
        _sdc_extracted_at,
        _sdc_received_at,
        _sdc_batched_at,
        JSON_VALUE(data, '$.acftype') AS aircraft_type,
        JSON_VALUE(data, '$.aerolinea') AS airline_name,
        JSON_VALUE(data, '$.arpt') AS airport_code,
        JSON_VALUE(data, '$.atda') AS atda_raw,
        JSON_VALUE(data, '$.belt') AS belt,
        JSON_VALUE(data, '$.destorig') AS origin_destination_city,
        JSON_VALUE(data, '$.estbr') AS estimated_status,
        JSON_VALUE(data, '$.estin') AS actual_status,
        JSON_VALUE(data, '$.estes') AS flight_status,
        JSON_VALUE(data, '$.etda') AS etda_raw,
        JSON_VALUE(data, '$.fetched_at') AS fetched_at_raw,
        JSON_VALUE(data, '$.gate') AS gate,
        JSON_VALUE(data, '$.IATAdestorig') AS origin_destination_code,
        JSON_VALUE(data, '$.idaerolinea') AS airline_code,
        JSON_VALUE(data, '$.id') AS flight_id,
        JSON_VALUE(data, '$.matricula') AS aircraft_registration,
        JSON_VALUE(data, '$.mov') AS movement_type,
        JSON_VALUE(data, '$.nro') AS flight_number,
        JSON_VALUE(data, '$.sdphrase') AS weather_description,
        JSON_VALUE(data, '$.sdtemp') AS weather_temp,
        JSON_VALUE(data, '$.sector') AS sector,
        JSON_VALUE(data, '$.stda') AS stda_raw,
        JSON_VALUE(data, '$.termsec') AS terminal,
        JSON_VALUE(data, '$.x_airport_iata') AS x_airport_iata,
        JSON_VALUE(data, '$.x_date') AS x_date,
        JSON_VALUE(data, '$.x_fetched_at') AS x_fetched_at_raw,
        JSON_VALUE(data, '$.x_movtp') AS x_movtp
    FROM source_rows
),

with_dates AS (
    SELECT
        flight_id,
        flight_number,
        airline_code,
        airline_name,
        airport_code,
        movement_type,
        origin_destination_code,
        origin_destination_city,
        _sdc_extracted_at,

        _sdc_received_at,
        _sdc_batched_at,

        aircraft_type,
        aircraft_registration,
        sector,
        gate,
        belt,
        terminal,
        weather_description,
        COALESCE(actual_status, estimated_status, flight_status) AS flight_status,
        SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%SZ', x_fetched_at_raw) AS x_fetched_at,
        SAFE.PARSE_DATE('%Y-%m-%d', x_date) AS flight_date,
        SAFE_CAST(weather_temp AS INT64) AS weather_temp,
        TIMESTAMP(
            CONCAT(x_date, ' ', SPLIT(stda_raw, ' ')[SAFE_OFFSET(1)], ':00')
        ) AS scheduled_timestamp,
        TIMESTAMP(
            CONCAT(x_date, ' ', SPLIT(etda_raw, ' ')[SAFE_OFFSET(1)], ':00')
        ) AS estimated_timestamp,
        TIMESTAMP(
            CONCAT(x_date, ' ', SPLIT(atda_raw, ' ')[SAFE_OFFSET(1)], ':00')
        ) AS actual_timestamp
    FROM parsed_json
),

with_delays AS (
    SELECT
        *,
        TIMESTAMP_DIFF(
            actual_timestamp,
            scheduled_timestamp,
            MINUTE
        ) AS delay_minutes
    FROM with_dates
),

with_flags AS (
    SELECT
        flight_id,
        flight_number,
        airline_code,
        airline_name,
        airport_code,
        movement_type,
        origin_destination_code,
        origin_destination_city,
        scheduled_timestamp,
        estimated_timestamp,
        actual_timestamp,
        delay_minutes,
        flight_date,
        flight_status,
        aircraft_type,
        aircraft_registration,
        sector,
        gate,
        belt,
        terminal,
        weather_temp,
        weather_description,
        x_fetched_at,
        _sdc_extracted_at,
        _sdc_received_at,
        _sdc_batched_at,
        CONCAT(
            flight_id, '-',
            flight_date, '-',
            airport_code, '-',
            movement_type
        ) AS flight_sk,
        flight_status IN ('Cancelado', 'Cancelled', 'C') AS is_cancelled,
        COALESCE(delay_minutes > 15, FALSE) AS is_delayed,
        CASE
            WHEN delay_minutes <= 0 THEN 'on_time'
            WHEN delay_minutes > 0 AND delay_minutes <= 15 THEN 'minor'
            WHEN delay_minutes > 15 AND delay_minutes <= 30 THEN 'minor'
            WHEN delay_minutes > 30 AND delay_minutes <= 60 THEN 'moderate'
            ELSE 'severe'
        END AS delay_category,
        CASE
            WHEN movement_type = 'A' THEN 'arrival'
            WHEN movement_type = 'D' THEN 'departure'
            ELSE 'unknown'
        END AS flight_direction,
        EXTRACT(HOUR FROM scheduled_timestamp) AS scheduled_hour,
        EXTRACT(DAYOFWEEK FROM flight_date) AS day_of_week,
        EXTRACT(MONTH FROM flight_date) AS month,
        EXTRACT(YEAR FROM flight_date) AS year
    FROM with_delays
),

ranked_flights AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY flight_sk
            ORDER BY _sdc_extracted_at DESC, x_fetched_at DESC
        ) AS flight_rank
    FROM with_flags
)

SELECT
    flight_id,
    flight_number,
    airline_code,
    airline_name,
    airport_code,
    movement_type,
    flight_direction,
    origin_destination_code,
    origin_destination_city,
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
    belt AS baggage_belt,
    weather_temp,
    weather_description,
    _sdc_extracted_at,
    _sdc_received_at,
    _sdc_batched_at,
    x_fetched_at AS fetched_at,
    flight_sk,
    CURRENT_TIMESTAMP() AS dbt_updated_at
FROM ranked_flights
WHERE flight_rank = 1
