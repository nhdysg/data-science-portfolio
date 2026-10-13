"""Run every query in sql/ and save results and charts:  python run_queries.py"""

from pathlib import Path

import duckdb
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

from build_db import DB_PATH, build

ROOT = Path(__file__).resolve().parent
SQL, TAB, FIG = ROOT / "sql", ROOT / "output" / "tables", ROOT / "output" / "figures"
BLUE, GREY, RED = "#2563EB", "#6B7280", "#DC2626"
plt.rcParams.update({"figure.dpi": 150, "axes.spines.top": False, "axes.spines.right": False,
                     "axes.grid": True, "grid.alpha": 0.3, "font.size": 10})


def run_all(con) -> dict[str, pd.DataFrame]:
    TAB.mkdir(parents=True, exist_ok=True)
    results = {}
    for path in sorted(SQL.glob("*.sql")):
        df = con.execute(path.read_text()).df()
        results[path.stem] = df
        df.to_csv(TAB / f"{path.stem}.csv", index=False)
        question = path.read_text().splitlines()[0].lstrip("- ").strip()
        (TAB / f"{path.stem}.md").write_text(f"**{question}**\n\n{df.to_markdown(index=False)}\n")
    return results


def charts(r: dict[str, pd.DataFrame]) -> None:
    FIG.mkdir(parents=True, exist_ok=True)

    h = r["03_delay_by_hour"]
    fig, ax = plt.subplots(figsize=(7, 4))
    ax.bar(h["scheduled_hour"], h["avg_dep_delay_min"], color=BLUE)
    ax.set(xlabel="Scheduled departure hour", ylabel="Average departure delay (min)",
           title="Delays build up through the day")
    ax.set_xticks(h["scheduled_hour"])
    fig.tight_layout(); fig.savefig(FIG / "delay_by_hour.png"); plt.close(fig)

    m = r["04_monthly_trend"]
    fig, ax = plt.subplots(figsize=(7, 4))
    colors = [RED if v < 0 else BLUE for v in m["vs_year_avg_pts"]]
    ax.bar(m["month_name"].str[:3], m["vs_year_avg_pts"], color=colors)
    ax.axhline(0, color="black", lw=0.8)
    ax.set(ylabel="On-time rate vs. year average (pts)",
           title="June, July and December are the worst months")
    fig.tight_layout(); fig.savefig(FIG / "monthly_on_time.png"); plt.close(fig)

    c = r["02_carrier_scorecard"].sort_values("on_time_pct")
    fig, ax = plt.subplots(figsize=(7, 4.5))
    ax.barh(c["airline"], c["on_time_pct"], color=BLUE)
    for y, (v, n) in enumerate(zip(c["on_time_pct"], c["flights"])):
        ax.text(v + 0.5, y, f"{v:.0f}%  ({n:,} flights)", va="center", fontsize=8)
    ax.set(xlabel="Flights arriving within 15 min of schedule (%)", xlim=(0, 100),
           title="Airline on-time performance from NYC, 2013")
    fig.tight_layout(); fig.savefig(FIG / "carrier_on_time.png"); plt.close(fig)

    p = r["07_delay_propagation"]
    fig, ax = plt.subplots(figsize=(7, 4))
    ax.bar(p["previous_departure"].str[3:], p["pct_departing_15_plus_late"], color=[GREY, BLUE, BLUE, RED])
    ax.set(xlabel="Same aircraft's previous NYC departure that day",
           ylabel="Next departure 15+ min late (%)", title="Delays snowball through an aircraft's day")
    fig.tight_layout(); fig.savefig(FIG / "delay_propagation.png"); plt.close(fig)


if __name__ == "__main__":
    if not DB_PATH.exists():
        build()
    con = duckdb.connect(str(DB_PATH), read_only=True)
    results = run_all(con)
    charts(results)
    for name, df in results.items():
        print(f"\n== {name}\n{df.to_string(index=False)}")
