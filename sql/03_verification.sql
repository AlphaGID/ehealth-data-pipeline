-- Rows per raw run
SELECT _TABLE_SUFFIX AS run_id, COUNT(*) AS rows_loaded, MIN(ingested_at) AS ingested_at
FROM `ehealth-pipeline.raw.covid_raw_*`
GROUP BY run_id;

-- Row counts per layer (staging should equal analytics + rejected for a single run)
SELECT 'staging' AS layer, COUNT(*) AS n FROM `ehealth-pipeline.staging.covid_countries_stg`
UNION ALL SELECT 'rejected', COUNT(*) FROM `ehealth-pipeline.monitoring.rejected_records`
UNION ALL SELECT 'analytics', COUNT(*) FROM `ehealth-pipeline.analytics.covid_country_daily`;

-- Sanity check on values
SELECT country, snapshot_date, cases, deaths, ROUND(case_fatality_pct, 2) AS cfr_pct
FROM `ehealth-pipeline.analytics.covid_country_daily`
ORDER BY cases DESC
LIMIT 5;

-- Rejection reasons
SELECT reason, COUNT(*) AS n
FROM `ehealth-pipeline.monitoring.rejected_records`
GROUP BY reason;
