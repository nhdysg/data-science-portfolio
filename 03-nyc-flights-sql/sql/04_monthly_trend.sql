-- Q4. Which months are worst, and how does each month compare with the year?
WITH monthly AS (
    SELECT
        month,
        count(*)                       AS flights,
        avg(on_time::INT)              AS on_time_rate,
        avg(cancelled::INT)            AS cancel_rate,
        avg(dep_delay)                 AS avg_dep_delay
    FROM flights_enriched
    GROUP BY month
)
SELECT
    month,
    monthname(make_date(2013, month, 1))                     AS month_name,
    flights,
    round(100 * on_time_rate, 1)                             AS on_time_pct,
    round(100 * (on_time_rate - avg(on_time_rate) OVER ()), 1) AS vs_year_avg_pts,
    round(100 * cancel_rate, 1)                              AS cancel_pct,
    round(avg_dep_delay, 1)                                  AS avg_dep_delay_min
FROM monthly
ORDER BY month;
