-- Q8. Which busy routes have the worst arrival performance?
-- Routes with at least one flight a day on average (365+ flights).
WITH routes AS (
    SELECT
        origin,
        dest,
        any_value(dest_name)               AS destination,
        count(*)                           AS flights,
        mode(carrier)                      AS main_carrier,
        avg(on_time::INT)                  AS on_time_rate,
        avg(arr_delay)                     AS avg_arr_delay
    FROM flights_enriched
    GROUP BY origin, dest
    HAVING count(*) >= 365
)
SELECT
    origin || '-' || dest                  AS route,
    destination,
    flights,
    main_carrier,
    round(100 * on_time_rate, 1)           AS on_time_pct,
    round(avg_arr_delay, 1)                AS avg_arr_delay_min,
    ntile(4) OVER (ORDER BY on_time_rate)  AS quartile    -- 1 = worst quarter of routes
FROM routes
ORDER BY on_time_rate
LIMIT 10;
