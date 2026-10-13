-- Q6. How much do rain and low visibility at departure raise delays?
-- Each flight is matched to the hourly weather observation at its origin airport.
WITH matched AS (
    SELECT
        f.dep_delay,
        f.cancelled,
        CASE
            WHEN w.visib < 1   THEN '1. < 1 mile'
            WHEN w.visib < 3   THEN '2. 1-3 miles'
            WHEN w.visib < 10  THEN '3. 3-10 miles'
            WHEN w.visib >= 10 THEN '4. 10 miles (clear)'
        END AS visibility,
        CASE
            WHEN w.precip = 0     THEN '1. none'
            WHEN w.precip < 0.1   THEN '2. light (< 0.1 in/h)'
            WHEN w.precip >= 0.1  THEN '3. heavy (>= 0.1 in/h)'
        END AS precipitation
    FROM flights_enriched f
    JOIN weather w USING (origin, time_hour)
)
SELECT 'visibility' AS factor, visibility AS level, count(*) AS flights,
       round(avg(dep_delay), 1) AS avg_dep_delay_min,
       round(100 * avg(cancelled::INT), 1) AS cancel_pct
FROM matched GROUP BY visibility
UNION ALL
SELECT 'precipitation', precipitation, count(*),
       round(avg(dep_delay), 1), round(100 * avg(cancelled::INT), 1)
FROM matched GROUP BY precipitation
ORDER BY factor DESC, level;
