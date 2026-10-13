-- Q3. Every K-pop song on the Hot 100: how high, how long, and with whom.
CREATE OR REPLACE TABLE kpop_songs AS
SELECT
    e.title,
    e.performer,
    t.segment,
    t.act_family,
    t.western_collab,
    min(e.chart_week)                       AS debut_week,
    year(min(e.chart_week))                 AS debut_year,
    arg_min(e.pos, e.chart_week)            AS debut_pos,
    min(e.pos)                              AS peak_pos,
    count(*)                                AS weeks_on_chart,
    max(e.chart_week) = (SELECT max(chart_week) FROM entries) AS still_charting
FROM entries e
JOIN performer_tags t USING (credit)
WHERE e.chart = 'hot100' AND t.kpop
GROUP BY ALL
ORDER BY weeks_on_chart DESC;
