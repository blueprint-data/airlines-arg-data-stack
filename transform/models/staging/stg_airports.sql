{{ config(
    tags=['staging']
) }}

WITH source_data AS (
    SELECT *
    FROM {{ ref('airports') }}
),

normalized AS (
    SELECT
        airport_name,
        city,
        region,
        country,
        timezone,
        UPPER(TRIM(airport_code)) AS airport_code,
        SAFE_CAST(latitude AS FLOAT64) AS latitude,
        SAFE_CAST(longitude AS FLOAT64) AS longitude,
        SAFE_CAST(is_international AS BOOL) AS is_international
    FROM source_data
    WHERE airport_code IS NOT NULL
),

final AS (
    SELECT
        airport_code,
        airport_name,
        city,
        region,
        country,
        latitude,
        longitude,
        timezone,
        COALESCE(is_international, FALSE) AS is_international,
        country = 'Argentina' AS is_argentine_airport,
        CURRENT_TIMESTAMP() AS dbt_updated_at
    FROM normalized
)

SELECT *
FROM final
