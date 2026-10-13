-- Q1. How do the three NYC airports compare on volume, punctuality and cancellations?
SELECT
    origin                                              AS airport,
    count(*)                                            AS scheduled_flights,
    round(100 * avg(cancelled::INT), 1)                 AS cancel_pct,
    round(100 * avg(on_time::INT), 1)                   AS on_time_pct,
    round(avg(dep_delay), 1)                            AS avg_dep_delay_min,
    round(quantile_cont(dep_delay, 0.9), 0)             AS p90_dep_delay_min
FROM flights_enriched
GROUP BY origin
ORDER BY on_time_pct DESC;
