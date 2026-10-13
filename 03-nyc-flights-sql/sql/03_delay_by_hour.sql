-- Q3. How does punctuality change over the day?
SELECT
    hour                                    AS scheduled_hour,
    count(*)                                AS flights,
    round(100 * avg(on_time::INT), 1)       AS on_time_pct,
    round(avg(dep_delay), 1)                AS avg_dep_delay_min,
    round(100 * avg(cancelled::INT), 1)     AS cancel_pct
FROM flights_enriched
WHERE hour BETWEEN 5 AND 23
GROUP BY hour
ORDER BY hour;
