{{ config(
    materialized='incremental',
    unique_key='airline_code',
    tags=['staging']
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
    FROM {{ ref('stg_flights') }} AS f
    {% if is_incremental() %}
        WHERE f._sdc_extracted_at > (
            SELECT le.last_value
            FROM last_extract AS le
        )
    {% endif %}
),

airlines_to_refresh AS (
    SELECT DISTINCT nf.airline_code
    FROM new_flights AS nf
    WHERE nf.airline_code IS NOT NULL
)

SELECT
    f.airline_code,
    MAX(f._sdc_extracted_at) AS _sdc_extracted_at,
    ANY_VALUE(f.airline_name) AS airline_name,
    COUNT(*) AS total_flights,
    COUNT(DISTINCT f.flight_id) AS unique_flights,
    COUNT(DISTINCT f.airport_code) AS unique_airports,
    COUNTIF(f.movement_type = 'A') AS total_arrivals,
    COUNTIF(f.movement_type = 'D') AS total_departures,
    AVG(f.delay_minutes) AS avg_delay_minutes,
    SUM(CASE WHEN f.is_cancelled THEN 1 ELSE 0 END) AS total_cancelled,
    SUM(CASE WHEN f.is_delayed THEN 1 ELSE 0 END) AS total_delayed,
    SUM(CASE WHEN NOT f.is_cancelled AND NOT f.is_delayed THEN 1 ELSE 0 END) AS total_on_time,
    COALESCE(
        CASE
            WHEN COUNTIF(f.movement_type = 'D') > 0
                THEN
                    SAFE_MULTIPLY(
                        SAFE_DIVIDE(
                            SUM(CASE WHEN NOT f.is_cancelled AND NOT f.is_delayed THEN 1 ELSE 0 END),
                            COUNTIF(f.movement_type = 'D')
                        ),
                        100.0
                    )
        END,
        0.0
    ) AS on_time_percentage,
    COALESCE(
        CASE
            WHEN COUNTIF(f.movement_type = 'D') > 0
                THEN
                    SAFE_MULTIPLY(
                        SAFE_DIVIDE(
                            SUM(CASE WHEN f.is_cancelled THEN 1 ELSE 0 END), COUNTIF(f.movement_type = 'D')
                        ),
                        100.0
                    )
        END,
        0.0
    ) AS cancellation_rate,
    COALESCE(
        CASE
            WHEN COUNTIF(f.movement_type = 'D') > 0
                THEN
                    SAFE_MULTIPLY(
                        SAFE_DIVIDE(
                            SUM(CASE WHEN f.is_delayed THEN 1 ELSE 0 END), COUNTIF(f.movement_type = 'D')
                        ),
                        100.0
                    )
        END,
        0.0
    ) AS delayed_percentage,
    MIN(f.flight_date) AS first_seen_date,
    MAX(f.flight_date) AS last_seen_date,
    CURRENT_TIMESTAMP() AS dbt_updated_at
FROM {{ ref('stg_flights') }} AS f
WHERE
    f.airline_code IN (
        SELECT ar.airline_code
        FROM airlines_to_refresh AS ar
    )
GROUP BY
    f.airline_code
