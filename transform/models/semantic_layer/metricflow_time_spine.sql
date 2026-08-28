{{ config(
    materialized='table',
    tags=['metricflow', 'semantic_layer']
) }}

SELECT date_day
FROM UNNEST(GENERATE_DATE_ARRAY('2020-01-01', '2030-12-31')) AS date_day