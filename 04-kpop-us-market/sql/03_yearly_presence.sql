-- Q1. How has K-pop's presence on the US charts grown?
-- Share = K-pop chart slots / all chart slots that year (e.g. 52 weeks x 200 for the album chart).
CREATE OR REPLACE TABLE yearly_presence AS
SELECT
    e.chart,
    year(e.chart_week)                                         AS year,
    count(DISTINCT e.title || '|' || e.performer) FILTER (WHERE t.kpop) AS kpop_titles,
    count(*) FILTER (WHERE t.kpop)                             AS kpop_chart_slots,
    count(*) FILTER (WHERE t.kpop AND e.pos <= 10)             AS kpop_top10_slots,
    round(100.0 * count(*) FILTER (WHERE t.kpop) / count(*), 2) AS kpop_share_pct
FROM entries e
JOIN performer_tags t USING (credit)
WHERE e.chart_week >= DATE '2009-01-01'
GROUP BY ALL
ORDER BY chart, year;
