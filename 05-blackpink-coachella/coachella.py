"""Functions for the BLACKPINK Coachella 2019 event study.

Each row of the raw data is one song in one country's Spotify weekly top 200.
The `Week` column is the last day of the chart week (see data/README.md).
"""
from __future__ import annotations

import numpy as np
import pandas as pd
import statsmodels.formula.api as smf

WEST = [
    "Canada", "United Kingdom", "Australia", "New Zealand", "Ireland", "Germany",
    "Netherlands", "Sweden", "Norway", "Denmark", "Finland", "France", "Spain",
    "Italy", "Belgium", "Austria", "Switzerland", "Portugal", "Iceland", "Luxembourg",
]
ASIA = [
    "Hong Kong", "Indonesia", "Japan", "Malaysia", "Philippines", "Singapore",
    "Taiwan", "Thailand", "Vietnam",
]
LATAM = [
    "Argentina", "Bolivia", "Brazil", "Chile", "Colombia", "Costa Rica",
    "Dominican Republic", "Ecuador", "Guatemala", "Honduras", "Mexico", "Nicaragua",
    "Panama", "Peru", "Paraguay", "El Salvador", "Uruguay",
]

# Songs on the Kill This Love EP (released 2019-04-05). Everything else is "catalog".
KTL_EP = {"KILL THIS LOVE", "DON'T KNOW WHAT TO DO", "KICK IT", "HOPE NOT", "DDU-DU DDU-DU - REMIX"}

# Chart weeks (labelled by their last day) that contain the two Coachella sets.
COACHELLA_WEEKS = ["2019-04-19", "2019-04-26"]


def region(country: str) -> str:
    if country == "United States":
        return "US"
    if country in WEST:
        return "West"
    if country in ASIA:
        return "Asia"
    if country in LATAM:
        return "LatAm"
    return "Other"


def load(path: str) -> pd.DataFrame:
    d = pd.read_csv(path)
    d["Week"] = pd.to_datetime(d["Week"])
    d["region"] = d["Country"].map(region)
    # Spotify renamed BLACKPINK's Korean tracks in Jan 2019 ("DDU-DU DDU-DU - KR Ver." -> "DDU-DU DDU-DU").
    d["song"] = d["Track Name"].str.replace(" - KR Ver.", "", regex=False).str.upper()
    return d


def retention(d: pd.DataFrame, artist: str, song: str, first_full_week: str) -> pd.DataFrame:
    """Per country: log(streams in full week 2 / streams in full week 1).

    Only countries where the song charted in both weeks are kept.
    """
    s = d[(d["Artist"] == artist) & (d["song"] == song.upper())]
    p = s.pivot_table(index="Country", columns="Week", values="Streams", aggfunc="sum")
    w1 = pd.Timestamp(first_full_week)
    w2 = w1 + pd.Timedelta(days=7)
    p = p.reindex(columns=[w1, w2]).dropna()
    return pd.DataFrame({
        "country": p.index,
        "region": [region(c) for c in p.index],
        "log_ret": np.log(p[w2] / p[w1]).to_numpy(),
    })


def pct(b: float) -> float:
    """A coefficient on a log outcome, as a percentage difference."""
    return 100 * (np.exp(b) - 1)


def compare(ktl: pd.DataFrame, bench: pd.DataFrame, control: list[str]) -> pd.DataFrame:
    """West (US + West) vs `control` regions.

    naive: KTL only, y ~ west.  -> how much better the West kept listeners.
    ddd:   KTL and the benchmark song, y ~ west * ktl.  -> the West's extra
           retention for KTL beyond what it shows for a song with no Coachella.
    """
    df = pd.concat([ktl.assign(ktl=1), bench.assign(ktl=0)])
    df = df[df["region"].isin(["US", "West"] + control)].copy()
    df["west"] = df["region"].isin(["US", "West"]).astype(int)
    out = []
    fits = [
        ("naive", smf.ols("log_ret ~ west", data=df[df.ktl == 1]).fit(cov_type="HC1"), "west"),
        ("ddd", smf.ols("log_ret ~ west * ktl", data=df).fit(cov_type="HC1"), "west:ktl"),
    ]
    for method, m, term in fits:
        lo, hi = m.conf_int().loc[term]
        out.append({
            "method": method,
            "estimate_pct": round(pct(m.params[term]), 1),
            "ci_low_pct": round(pct(lo), 1),
            "ci_high_pct": round(pct(hi), 1),
            "p_value": round(m.pvalues[term], 3),
            "n_obs": int(m.nobs),
        })
    return pd.DataFrame(out)


def decay_index(d: pd.DataFrame, artist: str, song: str, first_full_week: str, weeks: int = 8) -> pd.DataFrame:
    """Weekly streams by region, first full week = 100.

    Uses only countries where the song charted in every one of the `weeks`
    weeks, so a country dropping out of the top 200 does not look like a fall.
    """
    s = d[(d["Artist"] == artist) & (d["song"] == song.upper())]
    cols = pd.date_range(first_full_week, periods=weeks, freq="7D")
    p = s.pivot_table(index="Country", columns="Week", values="Streams", aggfunc="sum").reindex(columns=cols).dropna()
    g = p.groupby(p.index.map(region)).sum()
    idx = g.div(g.iloc[:, 0], axis=0) * 100
    n = p.index.map(region).value_counts()
    long = idx.stack().rename("index").reset_index()
    long.columns = ["region", "week", "index"]
    long["countries"] = long["region"].map(n)
    return long


def catalog_by_region(d: pd.DataFrame) -> pd.DataFrame:
    """Weekly streams of BLACKPINK songs released before 2019, by region."""
    s = d[(d["Artist"] == "BLACKPINK") & ~d["song"].isin(KTL_EP)]
    return s.groupby(["Week", "region"])["Streams"].sum().unstack(fill_value=0)
