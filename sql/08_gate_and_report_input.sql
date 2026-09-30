-- Query for the LAST BigQuery module in the Make scenario (quality gate + report input).
-- Statement 1 (gate): raises ERROR() if any test failed -> Make error route sends the alert.
-- Statement 2 (summary): its result is what the module returns, so the Gemini module
--   can map Rows > Fields > Value as the report input. Only reached when all tests pass.


SELECT
  IF(
    COUNTIF(test_result = 'FAIL') > 0,
    ERROR(CONCAT(
      'DATA QUALITY FAILED for run ', ANY_VALUE(run_id), ': ',
      STRING_AGG(IF(test_result = 'FAIL', CONCAT(test_name, ' (', actual, ')'), NULL), '; ')
    )),
    'all tests passed'
  ) AS gate
FROM `ehealth-pipeline.monitoring.dq_results`;


SELECT TO_JSON_STRING(STRUCT(
  (SELECT MAX(run_id) FROM `ehealth-pipeline.monitoring.dq_results`) AS run_id,

  (SELECT AS STRUCT
     COUNT(DISTINCT snapshot_date) AS snapshots_in_history,
     COUNT(*) AS analytics_rows_total
   FROM `ehealth-pipeline.analytics.covid_country_daily`) AS history,

  (SELECT AS STRUCT
     MAX(snapshot_date) AS latest_snapshot_date,
     COUNT(*) AS countries,
     SUM(cases) AS total_cases,
     SUM(deaths) AS total_deaths,
     ROUND(SAFE_DIVIDE(SUM(deaths), SUM(cases)) * 100, 2) AS global_case_fatality_pct
   FROM `ehealth-pipeline.analytics.covid_country_daily`
   WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM `ehealth-pipeline.analytics.covid_country_daily`)
  ) AS latest_snapshot,

  (WITH dates AS (
     SELECT
       MAX(snapshot_date) AS latest,
       (SELECT MAX(snapshot_date)
        FROM `ehealth-pipeline.analytics.covid_country_daily`
        WHERE snapshot_date < (SELECT MAX(snapshot_date) FROM `ehealth-pipeline.analytics.covid_country_daily`)
       ) AS previous
     FROM `ehealth-pipeline.analytics.covid_country_daily`
   ),
   joined AS (
     SELECT c.country, c.cases AS cases_latest, p.cases AS cases_previous
     FROM `ehealth-pipeline.analytics.covid_country_daily` c
     JOIN dates ON c.snapshot_date = dates.latest
     JOIN `ehealth-pipeline.analytics.covid_country_daily` p
       ON p.country = c.country AND p.snapshot_date = dates.previous
   )
   SELECT AS STRUCT
     (SELECT previous FROM dates) AS previous_snapshot_date,
     COUNT(*) AS countries_compared,
     COUNTIF(cases_latest != cases_previous) AS countries_with_changed_cases,
     SUM(cases_latest - cases_previous) AS total_cases_delta
   FROM joined
  ) AS change_vs_previous_snapshot,

  (SELECT ARRAY_AGG(STRUCT(test_name, test_result, expected, actual))
   FROM `ehealth-pipeline.monitoring.dq_results`) AS test_results,

  (SELECT ARRAY_AGG(STRUCT(reason, n))
   FROM (
     SELECT reason, COUNT(*) AS n
     FROM `ehealth-pipeline.monitoring.rejected_records`
     GROUP BY reason
   )) AS rejected_by_reason,

  (SELECT ARRAY_AGG(STRUCT(continent, countries, total_cases, total_deaths) ORDER BY total_cases DESC)
   FROM (
     SELECT COALESCE(continent, 'Unknown') AS continent,
            COUNT(*) AS countries, SUM(cases) AS total_cases, SUM(deaths) AS total_deaths
     FROM `ehealth-pipeline.analytics.covid_country_daily`
     WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM `ehealth-pipeline.analytics.covid_country_daily`)
     GROUP BY continent
   )) AS by_continent,

  (SELECT ARRAY_AGG(STRUCT(country, cases, deaths, case_fatality_pct) ORDER BY cases DESC)
   FROM (
     SELECT country, cases, deaths, ROUND(case_fatality_pct, 2) AS case_fatality_pct
     FROM `ehealth-pipeline.analytics.covid_country_daily`
     WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM `ehealth-pipeline.analytics.covid_country_daily`)
     ORDER BY cases DESC
     LIMIT 5
   )) AS top5_by_cases,

  (SELECT ARRAY_AGG(STRUCT(country, cases, deaths, case_fatality_pct) ORDER BY case_fatality_pct DESC)
   FROM (
     SELECT country, cases, deaths, ROUND(case_fatality_pct, 2) AS case_fatality_pct
     FROM `ehealth-pipeline.analytics.covid_country_daily`
     WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM `ehealth-pipeline.analytics.covid_country_daily`)
       AND cases >= 100000
     ORDER BY case_fatality_pct DESC
     LIMIT 5
   )) AS highest_fatality_among_large_outbreaks
)) AS summary_json;
