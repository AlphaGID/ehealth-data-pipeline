-- Builds ONE compact JSON summary of the latest pipeline state.
-- This is the input sent to the GPT model for the data quality report (Phase 7).
-- Values in analytics are CUMULATIVE totals per country, not daily figures.

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
