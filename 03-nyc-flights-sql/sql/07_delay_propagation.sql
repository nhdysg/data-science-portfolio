-- Q7. Do delays snowball? For each aircraft, compare a departure's delay with
-- the delay of the same plane's previous NYC departure earlier that day.
WITH sequenced AS (
    SELECT
        tailnum,
        flight_date,
        sched_dep_time,
        dep_delay,
        lag(dep_delay) OVER (
            PARTITION BY tailnum, flight_date
            ORDER BY sched_dep_time
        ) AS prev_dep_delay
    FROM flights_enriched
    WHERE tailnum IS NOT NULL AND NOT cancelled
)
SELECT
    CASE
        WHEN prev_dep_delay <= 0   THEN '1. on time or early'
        WHEN prev_dep_delay <= 15  THEN '2. 1-15 min late'
        WHEN prev_dep_delay <= 60  THEN '3. 16-60 min late'
        ELSE                            '4. > 60 min late'
    END                                     AS previous_departure,
    count(*)                                AS flights,
    round(avg(dep_delay), 1)                AS avg_dep_delay_min,
    round(100 * avg((dep_delay > 15)::INT), 1) AS pct_departing_15_plus_late
FROM sequenced
WHERE prev_dep_delay IS NOT NULL
GROUP BY 1
ORDER BY 1;
