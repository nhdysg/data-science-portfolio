-- One row per chart position per week, for both charts.
-- `credit` is the performer used for K-pop tagging. It equals `performer` except for
-- the KPop Demon Hunters soundtrack album, which Billboard credits to "Soundtrack".
CREATE OR REPLACE TABLE entries AS
WITH raw AS (
    SELECT 'hot100' AS chart, CAST(chart_week AS DATE) AS chart_week, current_week AS pos,
           title, performer, wks_on_chart
    FROM read_parquet('{raw}/hot100.parquet')
    UNION ALL
    SELECT 'billboard200', CAST(chart_week AS DATE), current_week,
           coalesce(title, '(untitled)'), performer, wks_on_chart
    FROM read_parquet('{raw}/billboard200.parquet')
)
SELECT
    *,
    CASE WHEN chart = 'billboard200' AND title = 'KPop Demon Hunters' AND performer = 'Soundtrack'
         THEN 'HUNTR/X' ELSE performer END AS credit
FROM raw;
