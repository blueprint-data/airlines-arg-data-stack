{{ config(
    materialized='incremental',
    unique_key='route_day_sk',
    tags=['marts', 'routes']
) }}

WITH last_extract AS (
    {% if is_incremental() %}
        SELECT COALESCE(MAX(_sdc_extracted_at), TIMESTAMP '1970-01-01 00:00:00+00') AS last_value
        FROM {{ this }}
    {% else %}
        SELECT TIMESTAMP '1970-01-01 00:00:00+00' AS last_value
    {% endif %}
),

new_flights AS (
    SELECT *
    FROM {{ ref('flights_performance') }}
    {% if is_incremental() %}
        WHERE _sdc_extracted_at > (
            SELECT le.last_value
            FROM last_extract AS le
        )
    {% endif %}
),

affected_routes AS (
    SELECT DISTINCT
        flight_date,
        airport_code AS origin_airport_code,
        origin_destination_code AS destination_airport_code,
        airline_code
    FROM new_flights
    WHERE
        movement_type = 'D'
        AND flight_date IS NOT NULL
        AND airport_code IS NOT NULL
        AND origin_destination_code IS NOT NULL
        AND airline_code IS NOT NULL
),

route_daily AS (
    SELECT
        f.flight_date,
        f.airport_code AS origin_airport_code,
        f.origin_destination_code AS destination_airport_code,
        f.airline_code,
        f.airline_name,
        COUNT(*) AS total_flights,
        SUM(
            CASE WHEN f.movement_actual_timestamp IS NOT NULL THEN 1 ELSE 0 END
        ) AS total_completed_flights,
        SUM(CASE WHEN f.is_cancelled THEN 1 ELSE 0 END) AS total_cancelled_flights,
        SUM(CASE WHEN f.is_delayed THEN 1 ELSE 0 END) AS total_delayed_flights,
        SUM(CASE WHEN NOT f.is_cancelled AND NOT f.is_delayed THEN 1 ELSE 0 END) AS total_on_time_flights,
        AVG(
            CASE
                WHEN f.movement_actual_timestamp IS NOT NULL THEN f.delay_minutes
            END
        ) AS avg_delay_minutes,
        MAX(f._sdc_extracted_at) AS _sdc_extracted_at,
        MAX(f._sdc_received_at) AS _sdc_received_at,
        MAX(f._sdc_batched_at) AS _sdc_batched_at,
        CURRENT_TIMESTAMP() AS dbt_updated_at
    FROM {{ ref('flights_performance') }} AS f
    WHERE
        f.movement_type = 'D'
        AND EXISTS (
            SELECT 1
            FROM affected_routes AS ar
            WHERE
                ar.flight_date = f.flight_date
                AND ar.origin_airport_code = f.airport_code
                AND ar.destination_airport_code = f.origin_destination_code
                AND ar.airline_code = f.airline_code
        )
    GROUP BY
        f.flight_date,
        f.airport_code,
        f.origin_destination_code,
        f.airline_code,
        f.airline_name
),

with_percentages AS (
    SELECT
        *,
        CONCAT(
            CAST(flight_date AS STRING), '-',
            origin_airport_code, '-',
            destination_airport_code, '-',
            airline_code
        ) AS route_day_sk,
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
    FROM route_daily
)

SELECT
    route_day_sk,
    flight_date,
    origin_airport_code,
    destination_airport_code,
    airline_code,
    airline_name,
    total_flights,
    total_completed_flights,
    total_cancelled_flights,
    total_delayed_flights,
    total_on_time_flights,
    avg_delay_minutes,
    on_time_percentage,
    delayed_percentage,
    cancellation_rate,
    _sdc_extracted_at,
    _sdc_received_at,
    _sdc_batched_at,
    dbt_updated_at
FROM with_percentages
