-- Q10. Is Newark late because of the airport, or because of which airlines fly there?
-- Expected on-time rate = what the airport would score if every flight performed
-- at its airline's NYC-wide average. Observed minus expected isolates the airport.
WITH carrier_rate AS (
    SELECT carrier, avg(on_time::INT) AS carrier_on_time
    FROM flights_enriched
    GROUP BY carrier
),
by_airport AS (
    SELECT
        f.origin,
        count(*)                                          AS flights,
        avg(f.on_time::INT)                               AS observed,
        avg(CASE WHEN f.on_time IS NOT NULL THEN c.carrier_on_time END) AS expected,
        avg((f.carrier = 'EV')::INT)                      AS expressjet_share
    FROM flights_enriched f
    JOIN carrier_rate c USING (carrier)
    GROUP BY f.origin
)
SELECT
    origin                                   AS airport,
    flights,
    round(100 * expressjet_share, 1)         AS expressjet_share_pct,
    round(100 * observed, 1)                 AS observed_on_time_pct,
    round(100 * expected, 1)                 AS expected_from_airline_mix_pct,
    round(100 * (observed - expected), 1)    AS airport_effect_pts
FROM by_airport
ORDER BY airport_effect_pts;
