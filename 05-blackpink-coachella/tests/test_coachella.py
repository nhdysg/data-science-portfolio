import sys
from pathlib import Path

import numpy as np
import pandas as pd

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import coachella as c  # noqa: E402

RAW = HERE / "data" / "raw" / "spotify_weekly_2019_blackpink_bts.csv"


def test_region_mapping():
    assert c.region("United States") == "US"
    assert c.region("Germany") == "West"
    assert c.region("Thailand") == "Asia"
    assert c.region("Mexico") == "LatAm"
    assert c.region("Turkey") == "Other"


def test_kr_ver_rename_is_merged():
    d = c.load(RAW)
    ddu = d[(d.Artist == "BLACKPINK") & (d.song == "DDU-DU DDU-DU")]
    # Before the Feb 2019 rename the track is "DDU-DU DDU-DU - KR Ver.", after it is "DDU-DU DDU-DU".
    assert ddu.Week.min() == pd.Timestamp("2019-01-04")
    assert ddu.Week.max() > pd.Timestamp("2019-02-01")


def test_week_label_is_last_day_of_week():
    # Kill This Love was released on the evening of 2019-04-05 (Korea). If the label were the first
    # day of the week, it could not appear in the week labelled 04-05. It does, only in Asia.
    d = c.load(RAW)
    first = d[(d.song == "KILL THIS LOVE") & (d.Week == "2019-04-05")]
    assert len(first) > 0
    assert set(first.region) == {"Asia"}


def test_retention_by_hand():
    d = c.load(RAW)
    r = c.retention(d, "BLACKPINK", "Kill This Love", "2019-04-12")
    us = d[(d.song == "KILL THIS LOVE") & (d.Country == "United States")].set_index("Week").Streams
    expected = np.log(us[pd.Timestamp("2019-04-19")] / us[pd.Timestamp("2019-04-12")])
    assert np.isclose(r.set_index("country").loc["United States", "log_ret"], expected)


def test_naive_estimate_equals_difference_in_means():
    # With one 0/1 regressor, OLS slope = difference of group means (same idea as lesson 1).
    d = c.load(RAW)
    ktl = c.retention(d, "BLACKPINK", "Kill This Love", "2019-04-12")
    bwl = c.retention(d, "BTS", "Boy With Luv (feat. Halsey)", "2019-04-19")
    res = c.compare(ktl, bwl, ["Asia"]).set_index("method")
    k = ktl[ktl.region.isin(["US", "West", "Asia"])]
    diff = k[k.region != "Asia"].log_ret.mean() - k[k.region == "Asia"].log_ret.mean()
    assert np.isclose(res.loc["naive", "estimate_pct"], round(c.pct(diff), 1))


def test_decay_index_starts_at_100():
    d = c.load(RAW)
    dec = c.decay_index(d, "BLACKPINK", "Kill This Love", "2019-04-12")
    first = dec[dec.week == pd.Timestamp("2019-04-12")]
    assert np.allclose(first["index"], 100)
