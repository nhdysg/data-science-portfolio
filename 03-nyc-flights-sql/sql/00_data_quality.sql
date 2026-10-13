-- Q0. Data quality checks run before any analysis.
SELECT 'flights: total rows' AS check_name, count(*)::VARCHAR AS result FROM flights
UNION ALL
SELECT 'flights: cancelled (no departure time)', count(*)::VARCHAR FROM flights WHERE dep_time IS NULL
UNION ALL
SELECT 'flights: departed but no arrival delay (diverted or missing)', count(*)::VARCHAR
FROM flights WHERE dep_time IS NOT NULL AND arr_delay IS NULL
UNION ALL
SELECT 'flights: missing tail number', count(*)::VARCHAR FROM flights WHERE tailnum IS NULL
UNION ALL
SELECT 'flights: tail number not in planes table', count(DISTINCT tailnum)::VARCHAR || ' aircraft'
FROM flights f WHERE tailnum IS NOT NULL AND NOT EXISTS (SELECT 1 FROM planes p WHERE p.tailnum = f.tailnum)
UNION ALL
SELECT 'flights: destination not in airports table', count(DISTINCT dest)::VARCHAR || ' airports'
FROM flights f WHERE NOT EXISTS (SELECT 1 FROM airports a WHERE a.faa = f.dest)
UNION ALL
SELECT 'flights: no matching hourly weather at origin', count(*)::VARCHAR
FROM flights f WHERE NOT EXISTS (SELECT 1 FROM weather w WHERE w.origin = f.origin AND w.time_hour = f.time_hour)
UNION ALL
SELECT 'weather: duplicate (origin, hour) rows', (count(*) - count(DISTINCT (origin, time_hour)))::VARCHAR FROM weather
UNION ALL
SELECT 'weather: implausible wind speed (> 100 mph)', count(*)::VARCHAR FROM weather WHERE wind_speed > 100;
