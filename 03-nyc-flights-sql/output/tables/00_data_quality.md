**Q0. Data quality checks run before any analysis.**

| check_name                                                   | result       |
|:-------------------------------------------------------------|:-------------|
| flights: total rows                                          | 336776       |
| flights: cancelled (no departure time)                       | 8255         |
| flights: departed but no arrival delay (diverted or missing) | 1175         |
| flights: missing tail number                                 | 2512         |
| flights: tail number not in planes table                     | 721 aircraft |
| flights: destination not in airports table                   | 4 airports   |
| flights: no matching hourly weather at origin                | 1556         |
| weather: duplicate (origin, hour) rows                       | 0            |
| weather: implausible wind speed (> 100 mph)                  | 1            |
