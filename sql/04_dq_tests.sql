-- Automated data quality tests.
-- Rebuilds monitoring.dq_results with the results for the LATEST run.
-- (Sandbox blocks INSERT, so this table holds the latest results only, not history.)

CREATE OR REPLACE TABLE `ehealth-pipeline.monitoring.dq_results` AS
WITH
latest AS (
  SELECT MAX(run_id) AS run_id
  FROM `ehealth-pipeline.staging.covid_countries_stg`
),
raw_latest AS (
  SELECT COUNT(*) AS n, MAX(ingested_at) AS ingested_at
  FROM `ehealth-pipeline.raw.covid_raw_*`
  WHERE _TABLE_SUFFIX = (SELECT run_id FROM latest)
),
stg_latest AS (
  SELECT
    COUNT(*) AS n,
    COUNTIF(reject_reason IS NULL) AS valid_n,
    COUNTIF(reject_reason IS NOT NULL) AS rejected_n
  FROM `ehealth-pipeline.staging.covid_countries_stg`
  WHERE run_id = (SELECT run_id FROM latest)
),
ana AS (
  SELECT
    COUNT(*) AS n,
    COUNTIF(last_run_id = (SELECT run_id FROM latest)) AS n_from_latest,
    COUNTIF(country IS NULL OR snapshot_date IS NULL OR cases IS NULL) AS null_keys,
    COUNTIF(cases < 0 OR deaths < 0) AS negative_counts,
    COUNTIF(deaths > cases) AS deaths_gt_cases,
    COUNTIF(snapshot_date > CURRENT_DATE()) AS future_dates,
    COUNTIF(case_fatality_pct < 0 OR case_fatality_pct > 100) AS bad_cfr,
    COUNTIF(population IS NULL OR population = 0) AS population_missing,
    MAX(source_updated_at) AS max_source_updated
  FROM `ehealth-pipeline.analytics.covid_country_daily`
),
dups AS (
  SELECT COUNT(*) AS n
  FROM (
    SELECT snapshot_date, country
    FROM `ehealth-pipeline.analytics.covid_country_daily`
    GROUP BY snapshot_date, country
    HAVING COUNT(*) > 1
  )
),
schema_chk AS (
  SELECT COUNT(*) AS missing_columns
  FROM UNNEST([
    'snapshot_date','country','iso2','iso3','continent','population',
    'cases','deaths','recovered','active','case_fatality_pct','loaded_at'
  ]) AS expected_col
  WHERE expected_col NOT IN (
    SELECT column_name
    FROM `ehealth-pipeline.analytics.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name = 'covid_country_daily'
  )
),
m AS (
  SELECT
    (SELECT run_id FROM latest) AS run_id,
    raw_latest.n AS raw_n,
    raw_latest.ingested_at AS raw_ingested_at,
    stg_latest.n AS stg_n,
    stg_latest.valid_n,
    stg_latest.rejected_n,
    ana.*,
    dups.n AS duplicate_keys,
    schema_chk.missing_columns
  FROM raw_latest, stg_latest, ana, dups, schema_chk
)
SELECT
  m.run_id,
  t.test_category,
  t.test_name,
  CASE WHEN t.passed THEN 'PASS' WHEN t.severity = 'WARN' THEN 'WARN' ELSE 'FAIL' END AS test_result,
  t.expected,
  t.actual,
  CURRENT_TIMESTAMP() AS tested_at
FROM m, UNNEST([
  STRUCT('reconciliation' AS test_category, 'raw_rows_equal_staging_rows' AS test_name,
         m.raw_n = m.stg_n AS passed, 'raw = staging' AS expected,
         CONCAT('raw=', CAST(m.raw_n AS STRING), ', staging=', CAST(m.stg_n AS STRING)) AS actual,
         'ERROR' AS severity),
  STRUCT('reconciliation', 'analytics_rows_equal_valid_staging_rows',
         m.n_from_latest = m.valid_n, 'analytics (this run) = valid staging rows',
         CONCAT('analytics=', CAST(m.n_from_latest AS STRING), ', valid=', CAST(m.valid_n AS STRING)),
         'ERROR'),
  STRUCT('uniqueness', 'no_duplicate_country_per_day',
         m.duplicate_keys = 0, '0 duplicate keys', CAST(m.duplicate_keys AS STRING), 'ERROR'),
  STRUCT('completeness', 'no_nulls_in_key_columns',
         m.null_keys = 0, '0 rows with NULL country/date/cases', CAST(m.null_keys AS STRING), 'ERROR'),
  STRUCT('validity', 'no_negative_counts',
         m.negative_counts = 0, '0 rows', CAST(m.negative_counts AS STRING), 'ERROR'),
  STRUCT('validity', 'deaths_not_greater_than_cases',
         m.deaths_gt_cases = 0, '0 rows', CAST(m.deaths_gt_cases AS STRING), 'ERROR'),
  STRUCT('validity', 'no_future_dates',
         m.future_dates = 0, '0 rows', CAST(m.future_dates AS STRING), 'ERROR'),
  STRUCT('validity', 'fatality_pct_between_0_and_100',
         m.bad_cfr = 0, '0 rows outside 0-100', CAST(m.bad_cfr AS STRING), 'ERROR'),
  STRUCT('freshness', 'ingested_within_26_hours',
         TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), m.raw_ingested_at, HOUR) <= 26,
         'latest ingestion <= 26h ago',
         CONCAT(CAST(TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), m.raw_ingested_at, HOUR) AS STRING), ' hours ago'),
         'ERROR'),
  STRUCT('freshness', 'source_updated_within_48_hours',
         TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), m.max_source_updated, HOUR) <= 48,
         'source data <= 48h old',
         CONCAT(CAST(TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), m.max_source_updated, HOUR) AS STRING), ' hours old'),
         'ERROR'),
  STRUCT('schema', 'expected_columns_present',
         m.missing_columns = 0, '0 missing columns', CAST(m.missing_columns AS STRING), 'ERROR'),
  STRUCT('quality', 'rejection_rate_at_most_5_pct',
         SAFE_DIVIDE(m.rejected_n, m.stg_n) <= 0.05, 'rejected <= 5% of rows',
         CONCAT(CAST(ROUND(SAFE_DIVIDE(m.rejected_n, m.stg_n) * 100, 2) AS STRING), '%'),
         'WARN'),
  STRUCT('quality', 'population_missing_at_most_5_pct',
         SAFE_DIVIDE(m.population_missing, m.n) <= 0.05, 'missing population <= 5% of rows',
         CONCAT(CAST(ROUND(SAFE_DIVIDE(m.population_missing, m.n) * 100, 2) AS STRING), '%'),
         'WARN')
]) AS t;
