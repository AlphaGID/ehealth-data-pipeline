-- Quality gate, run as the last BigQuery module in the Make scenario.
-- Returns 'all tests passed' when nothing failed.
-- If any test has result FAIL, ERROR() makes the query fail, which triggers the
-- Make error-handler route (email alert). WARN results do not trigger the alert.

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
