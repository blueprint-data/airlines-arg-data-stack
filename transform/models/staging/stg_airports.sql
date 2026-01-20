{{ config(
    materialized='view',
    tags=['staging']
) }}

WITH all_airports AS (
    SELECT
        airport_code,
        origin_destination_code AS airport_code_alt
    FROM {{ ref('stg_flights') }}

    UNION ALL

    SELECT
        origin_destination_code AS airport_code,
        airport_code AS airport_code_alt
    FROM {{ ref('stg_flights') }}
),

unique_airports AS (
    SELECT DISTINCT airport_code
    FROM all_airports
    WHERE COALESCE(NULLIF(airport_code, ''), airport_code_alt) IS NOT NULL
),

airport_stats AS (
    SELECT
        ua.airport_code,
        f.origin_destination_city,
        MIN(f.flight_date) AS first_seen_date,
        MAX(f.flight_date) AS last_seen_date,
        COUNT(*) AS total_flights,
        COUNT(DISTINCT f.airline_code) AS unique_airlines,
        COUNT(DISTINCT CASE WHEN f.movement_type = 'A' THEN f.flight_id END) AS total_arrivals,
        COUNT(DISTINCT CASE WHEN f.movement_type = 'D' THEN f.flight_id END) AS total_departures,
        AVG(CASE WHEN f.actual_timestamp IS NOT NULL THEN f.delay_minutes END) AS avg_delay_minutes,
        CURRENT_TIMESTAMP() AS dbt_updated_at
    FROM unique_airports AS ua
    LEFT JOIN {{ ref('stg_flights') }} AS f
        ON ua.airport_code = f.airport_code
    GROUP BY
        ua.airport_code,
        f.origin_destination_city
)

SELECT
    airport_code,
    origin_destination_city AS city,
    first_seen_date,
    last_seen_date,
    total_flights,
    unique_airlines,
    total_arrivals,
    total_departures,
    avg_delay_minutes,
    dbt_updated_at
FROM airport_stats
ORDER BY total_flights DESC
