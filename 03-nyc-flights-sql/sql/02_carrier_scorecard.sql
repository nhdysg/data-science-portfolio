-- Q2. Which airlines are the most and least reliable out of NYC?
-- Carriers with fewer than 1,000 flights are excluded as too small to rank.
WITH carrier_stats AS (
    SELECT
        carrier,
        airline,
        count(*)                              AS flights,
        avg(cancelled::INT)                   AS cancel_rate,
        avg(on_time::INT)                     AS on_time_rate,
        avg(arr_delay)                        AS avg_arr_delay
    FROM flights_enriched
    GROUP BY carrier, airline
    HAVING count(*) >= 1000
)
SELECT
    rank() OVER (ORDER BY on_time_rate DESC)            AS rank,
    carrier,
    airline,
    flights,
    round(100 * flights / sum(flights) OVER (), 1)      AS share_of_flights_pct,
    round(100 * on_time_rate, 1)                        AS on_time_pct,
    round(100 * cancel_rate, 1)                         AS cancel_pct,
    round(avg_arr_delay, 1)                             AS avg_arr_delay_min
FROM carrier_stats
ORDER BY rank;
