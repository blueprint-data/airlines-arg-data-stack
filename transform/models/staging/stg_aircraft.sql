{{ config(
    materialized='incremental',
    unique_key='aircraft_registration',
    incremental_strategy='insert_overwrite',
    partition_by={'field': 'aircraft_registration', 'data_type': 'string'},
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
    WHERE
        f.aircraft_registration IS NOT NULL
        AND f._sdc_extracted_at > (
            SELECT w.last_value
            FROM watermark AS w
        )
),

aircraft_data AS (
    SELECT DISTINCT
        f.aircraft_registration,
        f.aircraft_type,
        MIN(f.flight_date) OVER (PARTITION BY f.aircraft_registration) AS first_seen_date,
        MAX(f.flight_date) OVER (PARTITION BY f.aircraft_registration) AS last_seen_date,
        COUNT(*) OVER (PARTITION BY f.aircraft_registration) AS total_flights,
        CURRENT_TIMESTAMP() AS dbt_updated_at
    FROM {{ ref('stg_flights') }} AS f
    WHERE f.aircraft_registration IN (
        SELECT df.aircraft_registration
        FROM delta_flights AS df
    )
),

airline_mapping AS (
    SELECT
        aircraft_registration,
        airline_code,
        airline_name
    FROM (
        SELECT
            f.aircraft_registration,
            f.airline_code,
            f.airline_name,
            ROW_NUMBER() OVER (
                PARTITION BY f.aircraft_registration
                ORDER BY f.fetched_at DESC
            ) AS airline_rank
        FROM {{ ref('stg_flights') }} AS f
        WHERE f.aircraft_registration IN (
            SELECT df.aircraft_registration
            FROM delta_flights AS df
        )
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
