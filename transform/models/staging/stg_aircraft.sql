{{ config(
    materialized='view',
    tags=['staging']
) }}

WITH aircraft_data AS (
    SELECT DISTINCT
        aircraft_registration,
        aircraft_type,
        MIN(flight_date) OVER (PARTITION BY aircraft_registration) AS first_seen_date,
        MAX(flight_date) OVER (PARTITION BY aircraft_registration) AS last_seen_date,
        COUNT(*) OVER (PARTITION BY aircraft_registration) AS total_flights,
        CURRENT_TIMESTAMP() AS dbt_updated_at
    FROM {{ ref('stg_flights') }}
    WHERE aircraft_registration IS NOT NULL
),

airline_mapping AS (
    SELECT
        aircraft_registration,
        airline_code,
        airline_name
    FROM (
        SELECT
            aircraft_registration,
            airline_code,
            airline_name,
            ROW_NUMBER() OVER (
                PARTITION BY aircraft_registration
                ORDER BY fetched_at DESC
            ) AS airline_rank
        FROM {{ ref('stg_flights') }}
        WHERE aircraft_registration IS NOT NULL
    )
    WHERE airline_rank = 1
)

SELECT
    a.aircraft_registration,
    a.aircraft_type,
    a.first_seen_date,
    a.last_seen_date,
    a.total_flights,
    am.airline_code,
    am.airline_name,
    a.dbt_updated_at
FROM aircraft_data AS a
LEFT JOIN airline_mapping AS am ON a.aircraft_registration = am.aircraft_registration
ORDER BY a.total_flights DESC
