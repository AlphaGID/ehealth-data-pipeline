-- DEMO ONLY: creates a deliberately bad "latest" raw run to prove the pipeline
-- rejects bad records and the tests catch problems.
-- Its name sorts after real runs, so it is treated as the latest run.
--
-- After this: re-run 02_transform.sql, then 04_dq_tests.sql, then inspect dq_results.
-- Expected: rejected_records filled; reconciliation FAIL (duplicate); rejection-rate WARN.
--
-- CLEAN UP afterwards (run the DROP at the bottom, then re-run 02 and 04).

CREATE OR REPLACE TABLE `ehealth-pipeline.raw.covid_raw_20260930_235959` AS
SELECT
  CURRENT_TIMESTAMP() AS ingested_at,
  'manual_bad_data_test' AS source_url,
  payload
FROM UNNEST([
  -- valid record
  '{"updated":1790683906017,"country":"TestLand A","countryInfo":{"iso2":"TA","iso3":"TLA","lat":0,"long":0},"cases":1000,"deaths":10,"population":50000,"continent":"Africa"}',
  -- exact duplicate of the valid record (same country, same day)
  '{"updated":1790683906017,"country":"TestLand A","countryInfo":{"iso2":"TA","iso3":"TLA","lat":0,"long":0},"cases":1000,"deaths":10,"population":50000,"continent":"Africa"}',
  -- negative case count
  '{"updated":1790683906017,"country":"TestLand B","countryInfo":{"iso2":"TB","iso3":"TLB","lat":0,"long":0},"cases":-5,"deaths":1,"population":1000,"continent":"Asia"}',
  -- deaths exceed cases
  '{"updated":1790683906017,"country":"TestLand C","countryInfo":{"iso2":"TC","iso3":"TLC","lat":0,"long":0},"cases":10,"deaths":50,"population":1000,"continent":"Europe"}',
  -- missing country
  '{"updated":1790683906017,"countryInfo":{"iso2":"TD","iso3":"TLD","lat":0,"long":0},"cases":100,"deaths":1,"population":1000,"continent":"Asia"}',
  -- future date (2030-01-01)
  '{"updated":1893456000000,"country":"TestLand E","countryInfo":{"iso2":"TE","iso3":"TLE","lat":0,"long":0},"cases":100,"deaths":1,"population":1000,"continent":"Asia"}'
]) AS payload;

-- ===== CLEAN UP (run after the demo) =====
-- DROP TABLE IF EXISTS `ehealth-pipeline.raw.covid_raw_20260930_235959`;
