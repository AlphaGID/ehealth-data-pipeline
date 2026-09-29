-- Used in the Make.com "BigQuery > Run a Query" module.
-- {{HTTP Data}} is a Make mapping pill (HTTP module > Data), NOT literal text.
-- Map it by clicking between the r''' quotes and choosing Data from the HTTP module.
-- Creates one raw table per run, named covid_raw_<YYYYMMDD_HHMMSS>.

DECLARE payload_json STRING DEFAULT r'''{{HTTP Data}}''';

EXECUTE IMMEDIATE FORMAT("""
  CREATE TABLE `ehealth-pipeline.raw.covid_raw_%s` AS
  SELECT
    CURRENT_TIMESTAMP() AS ingested_at,
    'https://disease.sh/v3/covid-19/countries' AS source_url,
    item AS payload
  FROM UNNEST(JSON_EXTRACT_ARRAY(@j)) AS item
""", FORMAT_TIMESTAMP('%Y%m%d_%H%M%S', CURRENT_TIMESTAMP()))
USING payload_json AS j;
