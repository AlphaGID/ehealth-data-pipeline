-- Transformation: raw -> staging -> rejected / analytics / run log.
-- Safe to re-run: every statement is CREATE OR REPLACE (idempotent).

-- 1) STAGING: flatten JSON, cast types, flag bad rows (all runs, full history)
CREATE OR REPLACE TABLE `ehealth-pipeline.staging.covid_countries_stg` AS
WITH typed AS (
  SELECT
    _TABLE_SUFFIX AS run_id,
    ingested_at,
    TIMESTAMP_MILLIS(SAFE_CAST(JSON_VALUE(payload, '$.updated') AS INT64)) AS source_updated_at,
    DATE(TIMESTAMP_MILLIS(SAFE_CAST(JSON_VALUE(payload, '$.updated') AS INT64))) AS snapshot_date,
    NULLIF(TRIM(JSON_VALUE(payload, '$.country')), '') AS country,
    UPPER(NULLIF(TRIM(JSON_VALUE(payload, '$.countryInfo.iso2')), '')) AS iso2,
    UPPER(NULLIF(TRIM(JSON_VALUE(payload, '$.countryInfo.iso3')), '')) AS iso3,
    NULLIF(TRIM(JSON_VALUE(payload, '$.continent')), '') AS continent,
    SAFE_CAST(JSON_VALUE(payload, '$.countryInfo.lat') AS FLOAT64) AS latitude,
    SAFE_CAST(JSON_VALUE(payload, '$.countryInfo.long') AS FLOAT64) AS longitude,
    SAFE_CAST(JSON_VALUE(payload, '$.population') AS INT64) AS population,
    SAFE_CAST(JSON_VALUE(payload, '$.cases') AS INT64) AS cases,
    SAFE_CAST(JSON_VALUE(payload, '$.todayCases') AS INT64) AS today_cases,
    SAFE_CAST(JSON_VALUE(payload, '$.deaths') AS INT64) AS deaths,
    SAFE_CAST(JSON_VALUE(payload, '$.todayDeaths') AS INT64) AS today_deaths,
    SAFE_CAST(JSON_VALUE(payload, '$.recovered') AS INT64) AS recovered,
    SAFE_CAST(JSON_VALUE(payload, '$.active') AS INT64) AS active,
    SAFE_CAST(JSON_VALUE(payload, '$.critical') AS INT64) AS critical,
    SAFE_CAST(JSON_VALUE(payload, '$.tests') AS INT64) AS tests
  FROM `ehealth-pipeline.raw.covid_raw_*`
)
SELECT
  *,
  CASE
    WHEN country IS NULL THEN 'missing_country'
    WHEN snapshot_date IS NULL THEN 'missing_or_invalid_updated'
    WHEN snapshot_date > CURRENT_DATE() THEN 'future_date'
    WHEN cases IS NULL THEN 'missing_cases'
    WHEN cases < 0 OR deaths < 0 THEN 'negative_count'
    WHEN deaths > cases THEN 'deaths_exceed_cases'
  END AS reject_reason
FROM typed;

-- 2) REJECTED RECORDS: everything that failed a rule
CREATE OR REPLACE TABLE `ehealth-pipeline.monitoring.rejected_records` AS
SELECT run_id, ingested_at, reject_reason AS reason, country, TO_JSON_STRING(s) AS payload
FROM `ehealth-pipeline.staging.covid_countries_stg` AS s
WHERE reject_reason IS NOT NULL;

-- 3) ANALYTICS: valid rows only, latest record per country per day
CREATE OR REPLACE TABLE `ehealth-pipeline.analytics.covid_country_daily` AS
SELECT
  snapshot_date, country, iso2, iso3, continent, latitude, longitude,
  population, cases, today_cases, deaths, today_deaths, recovered, active, critical, tests,
  SAFE_DIVIDE(deaths, cases) * 100 AS case_fatality_pct,
  source_updated_at,
  run_id AS last_run_id,
  CURRENT_TIMESTAMP() AS loaded_at
FROM `ehealth-pipeline.staging.covid_countries_stg`
WHERE reject_reason IS NULL
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY snapshot_date, country ORDER BY ingested_at DESC
) = 1;

-- 4) RUN LOG: one row per raw run
CREATE OR REPLACE TABLE `ehealth-pipeline.monitoring.pipeline_run_log` AS
SELECT
  run_id,
  MIN(ingested_at) AS ingested_at,
  COUNT(*) AS rows_extracted,
  COUNTIF(reject_reason IS NULL) AS rows_valid,
  COUNTIF(reject_reason IS NOT NULL) AS rows_rejected
FROM `ehealth-pipeline.staging.covid_countries_stg`
GROUP BY run_id;
