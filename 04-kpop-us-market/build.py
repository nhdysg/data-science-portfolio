"""Build the analysis tables with SQL (DuckDB):  python build.py

Reads the Billboard chart snapshots in data/raw/, runs sql/*.sql in order,
and writes each analysis table to data/processed/ for the R models.
"""

from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent
RAW = ROOT / "data" / "raw"
PROCESSED = ROOT / "data" / "processed"
TABLES = ["yearly_presence", "albums", "album_trajectories", "kpop_songs", "act_balance"]


def build(db: str = ":memory:") -> duckdb.DuckDBPyConnection:
    con = duckdb.connect(db)
    con.execute(f"""
        CREATE OR REPLACE TABLE artists AS
        SELECT * REPLACE (CAST(valid_from AS DATE) AS valid_from)
        FROM read_csv('{(ROOT / "data" / "kpop_artists.csv").as_posix()}', header = true)
    """)
    for path in sorted((ROOT / "sql").glob("*.sql")):
        con.execute(path.read_text().replace("{raw}", RAW.as_posix()))
    return con


if __name__ == "__main__":
    con = build()
    PROCESSED.mkdir(parents=True, exist_ok=True)
    for t in TABLES:
        df = con.execute(f"SELECT * FROM {t}").df()
        df.to_csv(PROCESSED / f"{t}.csv", index=False)
        print(f"{t:<16} {len(df):>6,} rows")
