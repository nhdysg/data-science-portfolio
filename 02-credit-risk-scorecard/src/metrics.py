"""Model performance metrics used in credit risk validation."""

import numpy as np
import pandas as pd
from sklearn.metrics import roc_auc_score


def gini(y, p) -> float:
    return 2 * roc_auc_score(y, p) - 1


def ks_statistic(y, p) -> float:
    """Max distance between the cumulative score distributions of bads and goods."""
    y = np.asarray(y); p = np.asarray(p)
    order = np.argsort(p)
    y_sorted = y[order]
    cum_bad = np.cumsum(y_sorted) / y_sorted.sum()
    cum_good = np.cumsum(1 - y_sorted) / (1 - y_sorted).sum()
    # only evaluate at the last row of each tied score
    last = np.r_[np.diff(p[order]) != 0, True]
    return float(np.max(np.abs(cum_bad - cum_good)[last]))


def psi(expected, actual, n_bins: int = 10) -> float:
    """Population stability index of `actual` against `expected` (decile bins of expected)."""
    edges = np.unique(np.quantile(expected, np.linspace(0, 1, n_bins + 1)))
    edges[0], edges[-1] = -np.inf, np.inf
    e = np.histogram(expected, edges)[0] / len(expected)
    a = np.histogram(actual, edges)[0] / len(actual)
    e = np.clip(e, 1e-6, None); a = np.clip(a, 1e-6, None)
    return float(np.sum((a - e) * np.log(a / e)))


def decile_table(y, p, n: int = 10) -> pd.DataFrame:
    """Rank-order table: deciles of predicted risk, highest risk first."""
    df = pd.DataFrame({"y": np.asarray(y), "p": np.asarray(p)})
    df["decile"] = pd.qcut(df["p"].rank(method="first", ascending=False), n, labels=range(1, n + 1))
    t = df.groupby("decile", observed=True).agg(n=("y", "size"), defaults=("y", "sum"),
                                                mean_pd=("p", "mean"))
    t["default_rate"] = t["defaults"] / t["n"]
    t["cum_capture"] = t["defaults"].cumsum() / t["defaults"].sum()
    t["lift"] = t["default_rate"] / df["y"].mean()
    return t.reset_index()


def calibration_table(y, p, n: int = 10) -> pd.DataFrame:
    df = pd.DataFrame({"y": np.asarray(y), "p": np.asarray(p)})
    df["bin"] = pd.qcut(df["p"], n, duplicates="drop")
    return df.groupby("bin", observed=True).agg(predicted=("p", "mean"), observed=("y", "mean"),
                                                n=("y", "size")).reset_index(drop=True)


def summarize(name, y, p) -> dict:
    from sklearn.metrics import brier_score_loss
    return {"model": name, "auc": roc_auc_score(y, p), "gini": gini(y, p),
            "ks": ks_statistic(y, p), "brier": brier_score_loss(y, p)}
