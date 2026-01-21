{{ config(
    materialized='incremental',
    unique_key='airport_code',
    tags=['marts', 'airports']
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

affected_airports AS (
    SELECT DISTINCT nf.airport_code
    FROM new_flights AS nf
    WHERE nf.airport_code IS NOT NULL
    UNION ALL
    SELECT DISTINCT nf.origin_destination_code AS airport_code
    FROM new_flights AS nf
    WHERE nf.origin_destination_code IS NOT NULL
),

airport_operations AS (
    SELECT
        f.airport_code,
        COUNT(DISTINCT CASE WHEN f.movement_type = 'D' THEN f.flight_id END) AS total_departures,
        COUNT(DISTINCT CASE WHEN f.movement_type = 'A' THEN f.flight_id END) AS total_arrivals,
        AVG(CASE
            WHEN f.movement_type = 'D' AND f.actual_timestamp IS NOT NULL
                THEN f.delay_minutes
        END) AS avg_departure_delay_minutes,
        AVG(CASE
            WHEN f.movement_type = 'A' AND f.actual_timestamp IS NOT NULL
                THEN f.delay_minutes
        END) AS avg_arrival_delay_minutes,
        AVG(CASE WHEN f.actual_timestamp IS NOT NULL THEN f.delay_minutes END) AS avg_overall_delay_minutes,
        SUM(CASE WHEN f.is_cancelled THEN 1 ELSE 0 END) AS total_cancelled_flights,
        SUM(CASE WHEN f.is_delayed THEN 1 ELSE 0 END) AS total_delayed_flights,
        SUM(CASE WHEN NOT f.is_cancelled AND NOT f.is_delayed THEN 1 ELSE 0 END) AS total_on_time_flights,
        COUNT(DISTINCT f.airline_code) AS unique_airlines,
        COUNT(DISTINCT f.origin_destination_code) AS unique_destinations,
        MIN(f.flight_date) AS first_flight_date,
        MAX(f.flight_date) AS last_flight_date,
        MAX(f._sdc_extracted_at) AS _sdc_extracted_at,
        MAX(f._sdc_received_at) AS _sdc_received_at,
        MAX(f._sdc_batched_at) AS _sdc_batched_at,
        CURRENT_TIMESTAMP() AS dbt_updated_at
    FROM {{ ref('flights_performance') }} AS f
    WHERE
        f.airport_code IN (
            SELECT ah.airport_code
            FROM affected_airports AS ah
        )
    GROUP BY
        f.airport_code
),

departure_peak_hours AS (
    SELECT
        airport_code,
        ARRAY_AGG(hour_val ORDER BY freq DESC)[OFFSET(0)] AS peak_departure_hour
    FROM (
        SELECT
            f.airport_code,
            f.scheduled_hour AS hour_val,
            COUNT(*) AS freq
        FROM {{ ref('flights_performance') }} AS f
        WHERE
            f.movement_type = 'D'
            AND f.airport_code IN (
                SELECT ah.airport_code
                FROM affected_airports AS ah
            )
        GROUP BY
            f.airport_code,
            f.scheduled_hour
    ) AS departure_freq
    GROUP BY
        airport_code
),

arrival_peak_hours AS (
    SELECT
        airport_code,
        ARRAY_AGG(hour_val ORDER BY freq DESC)[OFFSET(0)] AS peak_arrival_hour
    FROM (
        SELECT
            f.airport_code,
            f.scheduled_hour AS hour_val,
            COUNT(*) AS freq
        FROM {{ ref('flights_performance') }} AS f
        WHERE
            f.movement_type = 'A'
            AND f.airport_code IN (
                SELECT ah.airport_code
                FROM affected_airports AS ah
            )
        GROUP BY
            f.airport_code,
            f.scheduled_hour
    ) AS arrival_freq
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
    _sdc_extracted_at,
    _sdc_received_at,
    _sdc_batched_at,
    dbt_updated_at
FROM with_rankings
ORDER BY (total_departures + total_arrivals) DESC
