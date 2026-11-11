# Data provenance

`raw/spotify_weekly_2019_blackpink_bts.csv` holds every BLACKPINK and BTS row from
`spotify-charts.csv` in [kiewic/spotify-charts](https://github.com/kiewic/spotify-charts)
(commit `b9901c1`, October 2019). That file is a scrape of spotifycharts.com: the weekly top 200
for 63 countries, from the week ending 2019-01-04 to the week ending 2019-10-18. It has no
Global chart. The full file is 62 MB, so only the two artists used here are kept.

Columns: `Country, Week, Position, Track Name, Artist, Streams, URL`.

**The `Week` date is the last day of the chart week.** We infer this from Kill This Love, which
was released on the evening of 2019-04-05 in Korea. It already appears in the week labelled
2019-04-05, with small stream counts and only in Asian countries. That is only possible if that
week ends on (and includes) April 5. A test in `tests/` checks this.

Only songs in a country's top 200 are recorded, so a song that falls out of the chart disappears
from the data rather than showing low streams.

To rebuild the subset from the full file:

```bash
git clone --depth 1 https://github.com/kiewic/spotify-charts
python -c "import pandas as pd; d=pd.read_csv('spotify-charts/spotify-charts.csv'); d[d.Artist.isin(['BLACKPINK','BTS'])].to_csv('data/raw/spotify_weekly_2019_blackpink_bts.csv', index=False)"
```
