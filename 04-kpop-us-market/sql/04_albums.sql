-- Q2. Album-level outcomes on the Billboard 200 for albums that debuted in the top 50
-- between 2018 and October 2025, so every album has a full year of follow-up.
CREATE OR REPLACE TABLE albums AS
WITH runs AS (
    SELECT
        title, performer,
        any_value(credit)                                AS credit,
        min(chart_week)                                  AS debut_week,
        arg_min(pos, chart_week)                         AS debut_pos,
        min(pos)                                         AS peak_pos,
        count(*)                                         AS total_weeks
    FROM entries
    WHERE chart = 'billboard200'
    GROUP BY title, performer
),
follow_up AS (
    SELECT
        r.title, r.performer,
        count(*) FILTER (WHERE e.chart_week < r.debut_week + INTERVAL 364 DAY) AS weeks_first_year,
        min(e.pos) FILTER (WHERE e.chart_week = r.debut_week + INTERVAL 7 DAY)  AS week2_pos
    FROM runs r
    JOIN entries e
      ON e.chart = 'billboard200' AND e.title = r.title AND e.performer = r.performer
    GROUP BY r.title, r.performer
)
SELECT
    r.title,
    r.performer,
    t.kpop,
    coalesce(t.segment, 'Not K-pop')                  AS segment,
    t.act_family,
    r.debut_week,
    year(r.debut_week)                                AS debut_year,
    r.debut_pos,
    r.peak_pos,
    coalesce(f.week2_pos, 201)                        AS week2_pos,   -- 201 = dropped off the chart
    f.week2_pos IS NULL                               AS off_chart_week2,
    f.weeks_first_year,
    r.total_weeks
FROM runs r
JOIN follow_up f USING (title, performer)
JOIN performer_tags t ON t.credit = r.credit
-- Billboard's own week counter must start at 1, which drops albums first charting before the data begins
JOIN entries d
  ON d.chart = 'billboard200' AND d.title = r.title AND d.performer = r.performer
 AND d.chart_week = r.debut_week AND d.wks_on_chart = 1
WHERE r.debut_week BETWEEN DATE '2018-01-01' AND DATE '2025-10-18'
  AND r.debut_pos <= 50;
