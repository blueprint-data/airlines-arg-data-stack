{{ config(
    materialized='incremental',
    unique_key='airport_code',
    tags=['staging']
) }}

WITH watermark AS (
    {% if is_incremental() %}
        SELECT COALESCE(MAX(_sdc_extracted_at), TIMESTAMP '1970-01-01 00:00:00+00') AS last_value
        FROM {{ this }}
    {% else %}
        SELECT TIMESTAMP '1970-01-01 00:00:00+00' AS last_value
    {% endif %}
),

delta_flights AS (
    SELECT *
    FROM {{ ref('stg_flights') }} AS f
    WHERE f._sdc_extracted_at > (
        SELECT w.last_value
        FROM watermark AS w
    )
),

airports_to_refresh AS (
    SELECT DISTINCT df.airport_code
    FROM delta_flights AS df
    WHERE df.airport_code IS NOT NULL
),

airport_stats AS (
    SELECT
        f.airport_code,
        MIN(f.flight_date) AS first_seen_date,
        MAX(f.flight_date) AS last_seen_date,
        COUNT(*) AS total_flights,
        COUNT(DISTINCT f.airline_code) AS unique_airlines,
        COUNT(DISTINCT CASE WHEN f.movement_type = 'A' THEN f.flight_id END) AS total_arrivals,
        COUNT(DISTINCT CASE WHEN f.movement_type = 'D' THEN f.flight_id END) AS total_departures,
        AVG(CASE WHEN f.actual_timestamp IS NOT NULL THEN f.delay_minutes END) AS avg_delay_minutes,
        MAX(f._sdc_extracted_at) AS _sdc_extracted_at,
        CURRENT_TIMESTAMP() AS dbt_updated_at
    FROM {{ ref('stg_flights') }} AS f
    WHERE
        f.airport_code IN (
            SELECT ar.airport_code
            FROM airports_to_refresh AS ar
        )
    GROUP BY
        f.airport_code
)

SELECT
    airport_code,
    first_seen_date,
    last_seen_date,
    total_flights,
    unique_airlines,
    total_arrivals,
    total_departures,
    avg_delay_minutes,
    _sdc_extracted_at,
    dbt_updated_at,
    CAST(NULL AS STRING) AS city
FROM airport_stats
ORDER BY total_flights DESC
