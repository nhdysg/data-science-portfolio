import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from src import data, metrics  # noqa: E402
from src.woe import WoeBinner, score, scorecard_points  # noqa: E402


@pytest.fixture(scope="module")
def df():
    return data.load()


def test_data_shape_and_default_rate(df):
    assert len(df) == 24_000
    assert df[data.TARGET].mean() == pytest.approx(0.221, abs=0.001)
    assert df[data.FEATURES].isna().sum().sum() == 0


def test_cleaning_folds_undocumented_codes(df):
    assert set(df["EDUCATION"].unique()) <= {1, 2, 3, 4}
    assert set(df["MARRIAGE"].unique()) <= {1, 2, 3}
    assert df[[f"PAY_{m}" for m in data.MONTHS]].min().min() == 0


def test_protected_attributes_are_not_features():
    assert not set(data.PROTECTED) & set(data.FEATURES)


def test_ks_perfect_and_random():
    y = np.array([0, 0, 0, 1, 1, 1])
    assert metrics.ks_statistic(y, np.array([.1, .2, .3, .7, .8, .9])) == pytest.approx(1.0)
    assert metrics.ks_statistic(y, np.full(6, 0.5)) == pytest.approx(0.0)


def test_gini_is_2auc_minus_1():
    y = np.array([0, 1, 0, 1])
    p = np.array([.2, .8, .4, .6])
    assert metrics.gini(y, p) == pytest.approx(1.0)


def test_psi_zero_for_identical_distributions():
    x = np.random.default_rng(0).normal(size=5000)
    assert metrics.psi(x, x) == pytest.approx(0.0, abs=1e-9)
    assert metrics.psi(x, x + 1) > 0.25  # a one-SD shift is a major shift


def test_woe_bins_are_monotonic_and_large_enough(df):
    X, y = df[["LIMIT_BAL", "utilization"]], df[data.TARGET]
    b = WoeBinner(max_bins=6, min_bin_share=0.05).fit(X, y)
    for col, t in b.tables_.items():
        assert (t["n"] / len(df)).min() >= 0.05
        d = np.diff(t["bad_rate"].to_numpy())
        assert (d >= 0).all() or (d <= 0).all(), col


def test_woe_sign_convention():
    # bin with more bads than average must have negative WOE
    x = pd.Series([0] * 50 + [1] * 50)
    y = pd.Series([0] * 45 + [1] * 5 + [0] * 20 + [1] * 30)
    b = WoeBinner(max_bins=2, min_bin_share=0.1).fit(x.to_frame("x"), y)
    t = b.tables_["x"]
    assert t["woe"].iloc[0] > 0 > t["woe"].iloc[1]


def test_scorecard_points_reproduce_model_log_odds(df):
    from sklearn.linear_model import LogisticRegression
    X, y = df[["PAY_1", "LIMIT_BAL"]], df[data.TARGET]
    b = WoeBinner().fit(X, y)
    W = b.transform(X)
    m = LogisticRegression(C=1e6, max_iter=1000).fit(W, y)
    pts = scorecard_points(b, pd.Series(m.coef_[0], index=W.columns), m.intercept_[0],
                           pdo=20, base_score=600, base_odds=50)
    s = score(pts, b, X)
    # score = offset + factor * log-odds(good)
    factor = 20 / np.log(2)
    offset = 600 - factor * np.log(50)
    log_odds_good = -m.decision_function(W)
    np.testing.assert_allclose(s.to_numpy(), offset + factor * log_odds_good, rtol=1e-6)
