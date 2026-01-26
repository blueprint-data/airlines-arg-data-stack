{{ config(
    materialized='incremental',
    unique_key=['analysis_type', 'dimension_1', 'dimension_2', 'dimension_3'],
    tags=['marts', 'delays']
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

affected_hourly AS (
    SELECT DISTINCT
        nf.flight_date,
        nf.scheduled_hour
    FROM new_flights AS nf
    WHERE
        nf.flight_date IS NOT NULL
        AND nf.scheduled_hour IS NOT NULL
),

affected_daily AS (
    SELECT DISTINCT
        nf.flight_date,
        nf.day_of_week
    FROM new_flights AS nf
    WHERE
        nf.flight_date IS NOT NULL
        AND nf.day_of_week IS NOT NULL
),

affected_routes AS (
    SELECT DISTINCT
        nf.airport_code,
        nf.origin_destination_code AS destination_code
    FROM new_flights AS nf
    WHERE
        nf.movement_type = 'D'
        AND nf.airport_code IS NOT NULL
        AND nf.origin_destination_code IS NOT NULL
),

affected_airline_delays AS (
    SELECT DISTINCT
        nf.airline_code,
        nf.airline_name,
        nf.day_of_week
    FROM new_flights AS nf
    WHERE
        nf.airline_code IS NOT NULL
        AND nf.day_of_week IS NOT NULL
),

affected_distribution AS (
    SELECT DISTINCT ad.delay_category
    FROM new_flights AS ad
    WHERE ad.delay_category IS NOT NULL
),

hourly_delays AS (
    SELECT
        flight_date,
        scheduled_hour,
        COUNT(*) AS total_flights,
        SUM(CASE WHEN is_delayed THEN 1 ELSE 0 END) AS total_delayed_flights,
        AVG(
            CASE
                WHEN delay_minutes BETWEEN -180 AND 600 THEN delay_minutes
            END
        ) AS avg_delay_minutes,
        AVG(
            CASE
                WHEN is_delayed AND delay_minutes BETWEEN -180 AND 600
                    THEN delay_minutes
            END
        ) AS avg_delay_when_delayed,
        SUM(CASE WHEN delay_category = 'severe' THEN 1 ELSE 0 END) AS severe_delays,
        SUM(CASE WHEN delay_category = 'moderate' THEN 1 ELSE 0 END) AS moderate_delays,
        SUM(CASE WHEN delay_category = 'minor' THEN 1 ELSE 0 END) AS minor_delays,
        MIN(delay_minutes) AS min_delay_minutes,
        MAX(delay_minutes) AS max_delay_minutes,
        MAX(f._sdc_extracted_at) AS _sdc_extracted_at,
        CURRENT_TIMESTAMP() AS dbt_updated_at
    FROM {{ ref('flights_performance') }} AS f
    WHERE
        EXISTS (
            SELECT 1
            FROM affected_hourly AS ah
            WHERE
                ah.flight_date = f.flight_date
                AND ah.scheduled_hour = f.scheduled_hour
        )
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
        AVG(
            CASE
                WHEN delay_minutes BETWEEN -180 AND 600 THEN delay_minutes
            END
        ) AS avg_delay_minutes,
        AVG(
            CASE
                WHEN is_delayed AND delay_minutes BETWEEN -180 AND 600
                    THEN delay_minutes
            END
        ) AS avg_delay_when_delayed,
        SUM(CASE WHEN delay_category = 'severe' THEN 1 ELSE 0 END) AS severe_delays,
        SUM(CASE WHEN delay_category = 'moderate' THEN 1 ELSE 0 END) AS moderate_delays,
        SUM(CASE WHEN delay_category = 'minor' THEN 1 ELSE 0 END) AS minor_delays,
        MAX(f._sdc_extracted_at) AS _sdc_extracted_at,
        CURRENT_TIMESTAMP() AS dbt_updated_at
    FROM {{ ref('flights_performance') }} AS f
    WHERE
        EXISTS (
            SELECT 1
            FROM affected_daily AS ad
            WHERE
                ad.flight_date = f.flight_date
                AND ad.day_of_week = f.day_of_week
        )
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
        AVG(
            CASE
                WHEN delay_minutes BETWEEN -180 AND 600 THEN delay_minutes
            END
        ) AS avg_delay_minutes,
        AVG(
            CASE
                WHEN is_delayed AND delay_minutes BETWEEN -180 AND 600
                    THEN delay_minutes
            END
        ) AS avg_delay_when_delayed,
        SUM(CASE WHEN delay_category = 'severe' THEN 1 ELSE 0 END) AS severe_delays,
        SUM(CASE WHEN delay_category = 'moderate' THEN 1 ELSE 0 END) AS moderate_delays,
        SUM(CASE WHEN delay_category = 'minor' THEN 1 ELSE 0 END) AS minor_delays,
        MIN(flight_date) AS first_seen_date,
        MAX(flight_date) AS last_seen_date,
        MAX(f._sdc_extracted_at) AS _sdc_extracted_at,
        CURRENT_TIMESTAMP() AS dbt_updated_at
    FROM {{ ref('flights_performance') }} AS f
    WHERE
        movement_type = 'D'
        AND EXISTS (
            SELECT 1
            FROM affected_routes AS ar
            WHERE
                ar.airport_code = f.airport_code
                AND ar.destination_code = f.origin_destination_code
        )
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
        AVG(
            CASE
                WHEN delay_minutes BETWEEN -180 AND 600 THEN delay_minutes
            END
        ) AS avg_delay_minutes,
        AVG(
            CASE
                WHEN is_delayed AND delay_minutes BETWEEN -180 AND 600
                    THEN delay_minutes
            END
        ) AS avg_delay_when_delayed,
        SUM(CASE WHEN delay_category = 'severe' THEN 1 ELSE 0 END) AS severe_delays,
        SUM(CASE WHEN delay_category = 'moderate' THEN 1 ELSE 0 END) AS moderate_delays,
        SUM(CASE WHEN delay_category = 'minor' THEN 1 ELSE 0 END) AS minor_delays,
        MAX(f._sdc_extracted_at) AS _sdc_extracted_at,
        CURRENT_TIMESTAMP() AS dbt_updated_at
    FROM {{ ref('flights_performance') }} AS f
    WHERE
        EXISTS (
            SELECT 1
            FROM affected_airline_delays AS aal
            WHERE
                aal.airline_code = f.airline_code
                AND aal.airline_name = f.airline_name
                AND aal.day_of_week = f.day_of_week
        )
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
        AVG(
            CASE
                WHEN delay_minutes BETWEEN -180 AND 600 THEN delay_minutes
            END
        ) AS avg_delay_minutes,
        AVG(
            CASE
                WHEN delay_minutes > 0 AND delay_minutes <= 600
                    THEN delay_minutes
            END
        ) AS avg_delay_when_delayed,
        MIN(delay_minutes) AS min_delay_minutes,
        MAX(delay_minutes) AS max_delay_minutes,
        MAX(f._sdc_extracted_at) AS _sdc_extracted_at,
        CURRENT_TIMESTAMP() AS dbt_updated_at
    FROM {{ ref('flights_performance') }} AS f
    WHERE
        delay_category IS NOT NULL
        AND EXISTS (
            SELECT 1
            FROM affected_distribution AS ad
            WHERE ad.delay_category = f.delay_category
        )
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
    _sdc_extracted_at,
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
    _sdc_extracted_at,
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
    _sdc_extracted_at,
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
    _sdc_extracted_at,
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
    _sdc_extracted_at,
    dbt_updated_at
FROM delay_distribution
