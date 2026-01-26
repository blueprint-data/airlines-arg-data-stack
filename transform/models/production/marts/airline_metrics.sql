{{ config(
    materialized='incremental',
    unique_key='airline_code',
    tags=['marts', 'airlines']
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

affected_airlines AS (
    SELECT DISTINCT airline_code
    FROM new_flights
    WHERE airline_code IS NOT NULL
),

airline_metrics AS (
    SELECT
        f.airline_code,
        f.airline_name,
        COUNT(*) AS total_flight_records,
        COUNT(DISTINCT flight_id) AS unique_flights,
        COUNT(DISTINCT CASE WHEN movement_type = 'D' THEN flight_id END) AS total_departures,
        COUNT(DISTINCT CASE WHEN movement_type = 'A' THEN flight_id END) AS total_arrivals,
        COUNT(DISTINCT airport_code) AS unique_airports,
        COUNT(DISTINCT origin_destination_code) AS unique_routes,
        AVG(CASE
            WHEN movement_type = 'D' AND movement_actual_timestamp IS NOT NULL
                THEN delay_minutes
        END) AS avg_departure_delay_minutes,
        AVG(CASE
            WHEN movement_type = 'A' AND movement_actual_timestamp IS NOT NULL
                THEN delay_minutes
        END) AS avg_arrival_delay_minutes,
        AVG(CASE
            WHEN movement_actual_timestamp IS NOT NULL
                THEN delay_minutes
        END) AS avg_overall_delay_minutes,
        SUM(CASE WHEN is_cancelled THEN 1 ELSE 0 END) AS total_cancelled_flights,
        SUM(CASE WHEN is_delayed THEN 1 ELSE 0 END) AS total_delayed_flights,
        SUM(CASE WHEN NOT is_cancelled AND NOT is_delayed THEN 1 ELSE 0 END) AS total_on_time_flights,
        SUM(CASE
            WHEN delay_category = 'severe' THEN 1
            ELSE 0
        END) AS total_severely_delayed_flights,
        SUM(CASE
            WHEN delay_category = 'moderate' THEN 1
            ELSE 0
        END) AS total_moderately_delayed_flights,
        MIN(flight_date) AS first_flight_date,
        MAX(flight_date) AS last_flight_date,
        MAX(f._sdc_extracted_at) AS _sdc_extracted_at,
        MAX(f._sdc_received_at) AS _sdc_received_at,
        MAX(f._sdc_batched_at) AS _sdc_batched_at,
        CURRENT_TIMESTAMP() AS dbt_updated_at
    FROM {{ ref('flights_performance') }} AS f
    WHERE
        f.airline_code IN (
            SELECT ai.airline_code
            FROM affected_airlines AS ai
        )
    GROUP BY
        f.airline_code,
        f.airline_name
),

with_percentages AS (
    SELECT
        *,
        CASE
            WHEN total_departures > 0
                THEN (total_on_time_flights * 100.0 / total_departures)
            ELSE 0
        END AS on_time_departure_percentage,
        CASE
            WHEN total_departures > 0
                THEN (total_delayed_flights * 100.0 / total_departures)
            ELSE 0
        END AS delayed_departure_percentage,
        CASE
            WHEN total_departures > 0
                THEN (total_cancelled_flights * 100.0 / total_departures)
            ELSE 0
        END AS cancellation_rate,
        CASE
            WHEN total_departures > 0
                THEN (total_severely_delayed_flights * 100.0 / total_departures)
            ELSE 0
        END AS severe_delay_rate
    FROM airline_metrics
),

with_rankings AS (
    SELECT
        *,
        RANK() OVER (ORDER BY on_time_departure_percentage DESC) AS on_time_rank,
        RANK() OVER (ORDER BY avg_departure_delay_minutes ASC) AS avg_delay_rank,
        RANK() OVER (ORDER BY unique_flights DESC) AS volume_rank
    FROM with_percentages
)

SELECT
    airline_code,
    airline_name,
    total_flight_records,
    unique_flights,
    total_departures,
    total_arrivals,
    unique_airports,
    unique_routes,
    avg_departure_delay_minutes,
    avg_arrival_delay_minutes,
    avg_overall_delay_minutes,
    total_cancelled_flights,
    total_delayed_flights,
    total_on_time_flights,
    total_severely_delayed_flights,
    total_moderately_delayed_flights,
    on_time_departure_percentage,
    delayed_departure_percentage,
    cancellation_rate,
    severe_delay_rate,
    on_time_rank,
    avg_delay_rank,
    volume_rank,
    first_flight_date,
    last_flight_date,
    _sdc_extracted_at,
    _sdc_received_at,
    _sdc_batched_at,
    dbt_updated_at
FROM with_rankings
ORDER BY total_departures DESC
