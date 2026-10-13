-- Week-by-week chart position for the first 12 weeks after debut, for albums that
-- debuted in the top 10. Weeks off the chart are recorded as position 201.
CREATE OR REPLACE TABLE album_trajectories AS
WITH top10 AS (
    SELECT title, performer, segment, kpop, debut_week
    FROM albums
    WHERE debut_pos <= 10
),
grid AS (
    SELECT t.*, w.week_index
    FROM top10 t, range(0, 13) AS w(week_index)
)
SELECT
    g.title,
    g.performer,
    g.segment,
    g.kpop,
    g.week_index,
    coalesce(e.pos, 201) AS pos
FROM grid g
LEFT JOIN entries e
       ON e.chart = 'billboard200'
      AND e.title = g.title
      AND e.performer = g.performer
      AND e.chart_week = g.debut_week + g.week_index * INTERVAL 7 DAY
ORDER BY g.title, g.performer, g.week_index;
