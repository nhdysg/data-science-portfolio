-- Q4. Album chart vs. song chart: where does each K-pop act's US success come from?
-- A collaboration counts toward every K-pop act family credited on it.
CREATE OR REPLACE TABLE act_balance AS
WITH performer_acts AS (
    SELECT DISTINCT c.credit, k.act_family, k.segment
    FROM credit_tokens c
    JOIN artists k ON k.credit_name = c.token AND c.first_week >= k.valid_from
)
SELECT
    a.act_family,
    any_value(a.segment)                                           AS segment,
    count(*) FILTER (WHERE e.chart = 'billboard200')               AS album_chart_weeks,
    count(*) FILTER (WHERE e.chart = 'hot100')                     AS song_chart_weeks,
    count(DISTINCT e.title) FILTER (WHERE e.chart = 'billboard200') AS albums_charted,
    count(DISTINCT e.title) FILTER (WHERE e.chart = 'hot100')      AS songs_charted,
    min(e.pos) FILTER (WHERE e.chart = 'billboard200')             AS best_album_pos,
    min(e.pos) FILTER (WHERE e.chart = 'hot100')                   AS best_song_pos
FROM entries e
JOIN performer_acts a USING (credit)
GROUP BY a.act_family
ORDER BY album_chart_weeks + song_chart_weeks DESC;
