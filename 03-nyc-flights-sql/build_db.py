"""Load the raw CSVs into a typed DuckDB database:  python build_db.py

Creates flights.duckdb with the five source tables plus one analysis view,
`flights_enriched`, that every query in sql/ builds on.
"""

from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent
RAW = ROOT / "data" / "raw"
DB_PATH = ROOT / "flights.duckdb"

SCHEMA = """
CREATE OR REPLACE TABLE airlines AS
SELECT * FROM read_csv('{raw}/airlines.csv', header = true, nullstr = 'NA');

CREATE OR REPLACE TABLE airports AS
SELECT * FROM read_csv('{raw}/airports.csv', header = true, nullstr = 'NA');

CREATE OR REPLACE TABLE planes AS
SELECT * FROM read_csv('{raw}/planes.csv', header = true, nullstr = 'NA');

CREATE OR REPLACE TABLE weather AS
SELECT * REPLACE (CAST(time_hour AS TIMESTAMP) AS time_hour)
FROM read_csv('{raw}/weather.csv', header = true, nullstr = 'NA');

-- flights.csv ships zipped; DuckDB cannot read .zip, so Python extracts it first
CREATE OR REPLACE TABLE flights AS
SELECT * REPLACE (CAST(time_hour AS TIMESTAMP) AS time_hour)
FROM read_csv('{flights_csv}', header = true, nullstr = 'NA');

-- One row per scheduled departure, with outcome flags used throughout.
--   cancelled: no actual departure time recorded
--   on_time:   arrived no more than 15 minutes late (the US DOT definition)
CREATE OR REPLACE VIEW flights_enriched AS
SELECT
    f.*,
    make_date(f.year, f.month, f.day)            AS flight_date,
    dayname(make_date(f.year, f.month, f.day))   AS weekday,
    f.dep_time IS NULL                           AS cancelled,
    CASE WHEN f.arr_delay IS NULL THEN NULL
         ELSE f.arr_delay <= 15 END              AS on_time,
    a.name                                       AS airline,
    d.name                                       AS dest_name
FROM flights f
LEFT JOIN airlines a ON a.carrier = f.carrier
LEFT JOIN airports d ON d.faa = f.dest;
"""


def build(db_path: Path = DB_PATH) -> Path:
    import tempfile
    import zipfile

    with tempfile.TemporaryDirectory() as tmp:
        with zipfile.ZipFile(RAW / "flights.csv.zip") as z:
            z.extract("flights.csv", tmp)
        con = duckdb.connect(str(db_path))
        con.execute(SCHEMA.format(raw=RAW.as_posix(), flights_csv=f"{tmp}/flights.csv"))
        con.close()
    return db_path


if __name__ == "__main__":
    path = build()
    con = duckdb.connect(str(path), read_only=True)
    for t in ["flights", "weather", "planes", "airports", "airlines"]:
        print(f"{t:<9} {con.execute(f'SELECT count(*) FROM {t}').fetchone()[0]:>9,} rows")
