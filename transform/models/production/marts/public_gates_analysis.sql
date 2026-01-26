{{ config(
    materialized='view',
    tags=['marts', 'public']
) }}

WITH base AS (
    SELECT
        delay_minutes,
        NULLIF(TRIM(gate), '') AS gate,
        COALESCE(
            movement_actual_timestamp,
            estimated_timestamp,
            scheduled_timestamp
        ) AS movement_timestamp
    FROM {{ ref('flights_performance') }}
),

with_hours AS (
    SELECT
        gate,
        delay_minutes,
        EXTRACT(HOUR FROM movement_timestamp) AS movement_hour
    FROM base
    WHERE gate IS NOT NULL
),

aggregated AS (
    SELECT
        gate,
        COUNT(*) AS total_flights,
        ROUND(
            AVG(
                CASE
                    WHEN delay_minutes BETWEEN -180 AND 600 THEN delay_minutes
                END
            ),
            1
        ) AS avg_delay_minutes,
        SUM(CASE WHEN delay_minutes > 0 THEN 1 ELSE 0 END) AS delayed_flights,
        SUM(CASE WHEN delay_minutes <= 0 THEN 1 ELSE 0 END) AS on_time_flights,
        ROUND(
            SAFE_DIVIDE(
                SUM(CASE WHEN delay_minutes <= 0 THEN 1 ELSE 0 END),
                COUNT(*)
            ) * 100,
            1
        ) AS on_time_percentage,
        MAX(delay_minutes) AS max_delay_minutes,
        [
            COUNTIF(movement_hour = 0),
            COUNTIF(movement_hour = 1),
            COUNTIF(movement_hour = 2),
            COUNTIF(movement_hour = 3),
            COUNTIF(movement_hour = 4),
            COUNTIF(movement_hour = 5),
            COUNTIF(movement_hour = 6),
            COUNTIF(movement_hour = 7),
            COUNTIF(movement_hour = 8),
            COUNTIF(movement_hour = 9),
            COUNTIF(movement_hour = 10),
            COUNTIF(movement_hour = 11),
            COUNTIF(movement_hour = 12),
            COUNTIF(movement_hour = 13),
            COUNTIF(movement_hour = 14),
            COUNTIF(movement_hour = 15),
            COUNTIF(movement_hour = 16),
            COUNTIF(movement_hour = 17),
            COUNTIF(movement_hour = 18),
            COUNTIF(movement_hour = 19),
            COUNTIF(movement_hour = 20),
            COUNTIF(movement_hour = 21),
            COUNTIF(movement_hour = 22),
            COUNTIF(movement_hour = 23)
        ] AS time_distribution
    FROM with_hours
    GROUP BY gate
)

SELECT
    gate,
    total_flights,
    avg_delay_minutes,
    delayed_flights,
    on_time_flights,
    on_time_percentage,
    max_delay_minutes,
    time_distribution
FROM aggregated
ORDER BY total_flights DESC
LIMIT 20
