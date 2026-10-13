-- Q9. When a flight leaves late, how much time does it make up in the air?
SELECT
    CASE
        WHEN distance < 500   THEN '1. < 500 mi'
        WHEN distance < 1000  THEN '2. 500-999 mi'
        WHEN distance < 2000  THEN '3. 1,000-1,999 mi'
        ELSE                       '4. 2,000+ mi'
    END                                          AS distance_band,
    count(*)                                     AS late_departures,
    round(avg(dep_delay), 1)                     AS avg_dep_delay_min,
    round(avg(arr_delay), 1)                     AS avg_arr_delay_min,
    round(avg(dep_delay - arr_delay), 1)         AS minutes_recovered
FROM flights_enriched
WHERE dep_delay > 15 AND arr_delay IS NOT NULL
GROUP BY 1
ORDER BY 1;
