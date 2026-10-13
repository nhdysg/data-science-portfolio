-- Q5. What happened on the ten worst days of the year?
-- Joins each day's flights to that day's weather at the departure airports.
WITH daily AS (
    SELECT
        flight_date,
        count(*)                        AS flights,
        avg(cancelled::INT)             AS cancel_rate,
        avg(dep_delay)                  AS avg_dep_delay
    FROM flights_enriched
    GROUP BY flight_date
),
daily_weather AS (
    SELECT
        make_date(year, month, day)     AS flight_date,
        sum(precip) / 3                 AS precip_in,     -- average of 3 airports' daily totals
        max(wind_speed) FILTER (WHERE wind_speed < 100) AS max_wind_mph,  -- drops a 1,048 mph sensor error
        min(visib)                      AS min_visibility_mi
    FROM weather
    GROUP BY 1
),
ranked AS (
    SELECT
        d.*,
        w.precip_in, w.max_wind_mph, w.min_visibility_mi,
        row_number() OVER (ORDER BY d.avg_dep_delay DESC) AS delay_rank
    FROM daily d
    LEFT JOIN daily_weather w USING (flight_date)
)
SELECT
    delay_rank,
    flight_date,
    dayname(flight_date)                AS weekday,
    flights,
    round(100 * cancel_rate, 1)         AS cancel_pct,
    round(avg_dep_delay, 1)             AS avg_dep_delay_min,
    round(precip_in, 2)                 AS precip_in,
    round(max_wind_mph, 0)              AS max_wind_mph,
    round(min_visibility_mi, 1)         AS min_visibility_mi
FROM ranked
WHERE delay_rank <= 10
ORDER BY delay_rank;
