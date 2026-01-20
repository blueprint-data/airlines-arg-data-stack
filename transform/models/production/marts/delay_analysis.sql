{{ config(
    materialized='table',
    tags=['marts', 'delays']
) }}

WITH hourly_delays AS (
    SELECT
        flight_date,
        scheduled_hour,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN is_delayed THEN 1 ELSE 0 END) AS total_delayed_flights,
        AVG(delay_minutes) AS avg_delay_minutes,
        AVG(CASE WHEN is_delayed THEN delay_minutes END) AS avg_delay_when_delayed,
        SUM(CASE WHEN delay_category = 'severe' THEN 1 ELSE 0 END) AS severe_delays,
        SUM(CASE WHEN delay_category = 'moderate' THEN 1 ELSE 0 END) AS moderate_delays,
        SUM(CASE WHEN delay_category = 'minor' THEN 1 ELSE 0 END) AS minor_delays,
        MIN(delay_minutes) AS min_delay_minutes,
        MAX(delay_minutes) AS max_delay_minutes,
        CURRENT_TIMESTAMP() AS dbt_updated_at
    FROM {{ ref('flights_performance') }}
    GROUP BY
        flight_date,
        scheduled_hour
),

daily_delays AS (
    SELECT
        flight_date,
        day_of_week,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN is_delayed THEN 1 ELSE 0 END) AS total_delayed_flights,
        AVG(delay_minutes) AS avg_delay_minutes,
        AVG(CASE WHEN is_delayed THEN delay_minutes END) AS avg_delay_when_delayed,
        SUM(CASE WHEN delay_category = 'severe' THEN 1 ELSE 0 END) AS severe_delays,
        SUM(CASE WHEN delay_category = 'moderate' THEN 1 ELSE 0 END) AS moderate_delays,
        SUM(CASE WHEN delay_category = 'minor' THEN 1 ELSE 0 END) AS minor_delays,
        CURRENT_TIMESTAMP() AS dbt_updated_at
    FROM {{ ref('flights_performance') }}
    GROUP BY
        flight_date,
        day_of_week
),

route_delays AS (
    SELECT
        airport_code,
        origin_destination_code AS destination_code,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN is_delayed THEN 1 ELSE 0 END) AS total_delayed_flights,
        AVG(delay_minutes) AS avg_delay_minutes,
        AVG(CASE WHEN is_delayed THEN delay_minutes END) AS avg_delay_when_delayed,
        SUM(CASE WHEN delay_category = 'severe' THEN 1 ELSE 0 END) AS severe_delays,
        SUM(CASE WHEN delay_category = 'moderate' THEN 1 ELSE 0 END) AS moderate_delays,
        SUM(CASE WHEN delay_category = 'minor' THEN 1 ELSE 0 END) AS minor_delays,
        MIN(flight_date) AS first_seen_date,
        MAX(flight_date) AS last_seen_date,
        CURRENT_TIMESTAMP() AS dbt_updated_at
    FROM {{ ref('flights_performance') }}
    WHERE movement_type = 'D'
    GROUP BY
        airport_code,
        origin_destination_code
),

airline_delays AS (
    SELECT
        airline_code,
        airline_name,
        day_of_week,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN is_delayed THEN 1 ELSE 0 END) AS total_delayed_flights,
        AVG(delay_minutes) AS avg_delay_minutes,
        AVG(CASE WHEN is_delayed THEN delay_minutes END) AS avg_delay_when_delayed,
        SUM(CASE WHEN delay_category = 'severe' THEN 1 ELSE 0 END) AS severe_delays,
        SUM(CASE WHEN delay_category = 'moderate' THEN 1 ELSE 0 END) AS moderate_delays,
        SUM(CASE WHEN delay_category = 'minor' THEN 1 ELSE 0 END) AS minor_delays,
        CURRENT_TIMESTAMP() AS dbt_updated_at
    FROM {{ ref('flights_performance') }}
    GROUP BY
        airline_code,
        airline_name,
        day_of_week
),

delay_distribution AS (
    SELECT
        delay_category,
        COUNT(*) AS total_flights,
        ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
        AVG(delay_minutes) AS avg_delay_minutes,
        AVG(CASE WHEN delay_minutes > 0 THEN delay_minutes END) AS avg_delay_when_delayed,
        MIN(delay_minutes) AS min_delay_minutes,
        MAX(delay_minutes) AS max_delay_minutes,
        CURRENT_TIMESTAMP() AS dbt_updated_at
    FROM {{ ref('flights_performance') }}
    WHERE delay_minutes IS NOT NULL
    GROUP BY
        delay_category
)

SELECT
    'hourly' AS analysis_type,
    CAST(flight_date AS STRING) AS dimension_1,
    CAST(scheduled_hour AS STRING) AS dimension_2,
    NULL AS dimension_3,
    total_flights,
    total_delayed_flights,
    avg_delay_minutes,
    avg_delay_when_delayed,
    severe_delays,
    moderate_delays,
    minor_delays,
    min_delay_minutes,
    max_delay_minutes,
    NULL AS first_seen_date,
    NULL AS last_seen_date,
    dbt_updated_at
FROM hourly_delays

UNION ALL

SELECT
    'daily' AS analysis_type,
    CAST(flight_date AS STRING) AS dimension_1,
    CAST(day_of_week AS STRING) AS dimension_2,
    NULL AS dimension_3,
    total_flights,
    total_delayed_flights,
    avg_delay_minutes,
    avg_delay_when_delayed,
    severe_delays,
    moderate_delays,
    minor_delays,
    NULL AS min_delay_minutes,
    NULL AS max_delay_minutes,
    NULL AS first_seen_date,
    NULL AS last_seen_date,
    dbt_updated_at
FROM daily_delays

UNION ALL

SELECT
    'route' AS analysis_type,
    airport_code AS dimension_1,
    destination_code AS dimension_2,
    NULL AS dimension_3,
    total_flights,
    total_delayed_flights,
    avg_delay_minutes,
    avg_delay_when_delayed,
    severe_delays,
    moderate_delays,
    minor_delays,
    NULL AS min_delay_minutes,
    NULL AS max_delay_minutes,
    first_seen_date,
    last_seen_date,
    dbt_updated_at
FROM route_delays

UNION ALL

SELECT
    'airline' AS analysis_type,
    airline_code AS dimension_1,
    airline_name AS dimension_2,
    CAST(day_of_week AS STRING) AS dimension_3,
    total_flights,
    total_delayed_flights,
    avg_delay_minutes,
    avg_delay_when_delayed,
    severe_delays,
    moderate_delays,
    minor_delays,
    NULL AS min_delay_minutes,
    NULL AS max_delay_minutes,
    NULL AS first_seen_date,
    NULL AS last_seen_date,
    dbt_updated_at
FROM airline_delays

UNION ALL

SELECT
    'distribution' AS analysis_type,
    delay_category AS dimension_1,
    NULL AS dimension_2,
    NULL AS dimension_3,
    total_flights,
    NULL AS total_delayed_flights,
    avg_delay_minutes,
    avg_delay_when_delayed,
    NULL AS severe_delays,
    NULL AS moderate_delays,
    NULL AS minor_delays,
    min_delay_minutes,
    max_delay_minutes,
    NULL AS first_seen_date,
    NULL AS last_seen_date,
    dbt_updated_at
FROM delay_distribution
