{{ config(
    materialized='table',
    tags=['marts', 'airports']
) }}

WITH airport_operations AS (
    SELECT
        airport_code,
        COUNT(DISTINCT CASE WHEN movement_type = 'D' THEN flight_id END) AS total_departures,
        COUNT(DISTINCT CASE WHEN movement_type = 'A' THEN flight_id END) AS total_arrivals,
        AVG(CASE
            WHEN movement_type = 'D' AND actual_timestamp IS NOT NULL
                THEN delay_minutes
        END) AS avg_departure_delay_minutes,
        AVG(CASE
            WHEN movement_type = 'A' AND actual_timestamp IS NOT NULL
                THEN delay_minutes
        END) AS avg_arrival_delay_minutes,
        AVG(CASE WHEN actual_timestamp IS NOT NULL THEN delay_minutes END) AS avg_overall_delay_minutes,
        SUM(CASE WHEN is_cancelled THEN 1 ELSE 0 END) AS total_cancelled_flights,
        SUM(CASE WHEN is_delayed THEN 1 ELSE 0 END) AS total_delayed_flights,
        SUM(CASE WHEN NOT is_cancelled AND NOT is_delayed THEN 1 ELSE 0 END) AS total_on_time_flights,
        COUNT(DISTINCT airline_code) AS unique_airlines,
        COUNT(DISTINCT origin_destination_code) AS unique_destinations,
        MIN(flight_date) AS first_flight_date,
        MAX(flight_date) AS last_flight_date,
        CURRENT_TIMESTAMP() AS dbt_updated_at
    FROM {{ ref('flights_performance') }}
    GROUP BY
        airport_code
),

departure_peak_hours AS (
    SELECT
        airport_code,
        ARRAY_AGG(hour_val ORDER BY freq DESC)[OFFSET(0)] AS peak_departure_hour
    FROM (
        SELECT
            airport_code,
            scheduled_hour AS hour_val,
            COUNT(*) AS freq
        FROM {{ ref('flights_performance') }}
        WHERE movement_type = 'D'
        GROUP BY
            airport_code,
            scheduled_hour
    )
    GROUP BY
        airport_code
),

arrival_peak_hours AS (
    SELECT
        airport_code,
        ARRAY_AGG(hour_val ORDER BY freq DESC)[OFFSET(0)] AS peak_arrival_hour
    FROM (
        SELECT
            airport_code,
            scheduled_hour AS hour_val,
            COUNT(*) AS freq
        FROM {{ ref('flights_performance') }}
        WHERE movement_type = 'A'
        GROUP BY
            airport_code,
            scheduled_hour
    )
    GROUP BY
        airport_code
),

with_percentages AS (
    SELECT
        ao.*,
        dph.peak_departure_hour,
        aph.peak_arrival_hour,
        CASE
            WHEN ao.total_departures > 0
                THEN (ao.total_on_time_flights * 100.0 / ao.total_departures)
            ELSE 0
        END AS on_time_departure_percentage,
        CASE
            WHEN ao.total_departures > 0
                THEN (ao.total_delayed_flights * 100.0 / ao.total_departures)
            ELSE 0
        END AS delayed_departure_percentage,
        CASE
            WHEN ao.total_departures > 0
                THEN (ao.total_cancelled_flights * 100.0 / ao.total_departures)
            ELSE 0
        END AS cancellation_rate
    FROM airport_operations AS ao
    LEFT JOIN departure_peak_hours AS dph ON ao.airport_code = dph.airport_code
    LEFT JOIN arrival_peak_hours AS aph ON ao.airport_code = aph.airport_code
),

with_rankings AS (
    SELECT
        *,
        RANK() OVER (ORDER BY on_time_departure_percentage DESC) AS on_time_rank,
        RANK() OVER (ORDER BY avg_departure_delay_minutes ASC) AS avg_delay_rank,
        RANK() OVER (ORDER BY (total_departures + total_arrivals) DESC) AS volume_rank
    FROM with_percentages
)

SELECT
    airport_code,
    total_departures,
    total_arrivals,
    avg_departure_delay_minutes,
    avg_arrival_delay_minutes,
    avg_overall_delay_minutes,
    total_cancelled_flights,
    total_delayed_flights,
    total_on_time_flights,
    unique_airlines,
    unique_destinations,
    peak_departure_hour,
    peak_arrival_hour,
    on_time_departure_percentage,
    delayed_departure_percentage,
    cancellation_rate,
    on_time_rank,
    avg_delay_rank,
    volume_rank,
    first_flight_date,
    last_flight_date,
    dbt_updated_at
FROM with_rankings
ORDER BY (total_departures + total_arrivals) DESC
