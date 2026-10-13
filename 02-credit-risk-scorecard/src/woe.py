"""Weight-of-evidence binning and a points-based scorecard."""

from dataclasses import dataclass, field

import numpy as np
import pandas as pd

EPS = 0.5  # added to good/bad counts so an all-good or all-bad bin has finite WOE


@dataclass
class WoeBinner:
    """Bin each feature, then replace values by the bin's weight of evidence.

    WOE = ln(share of goods in bin / share of bads in bin), so higher WOE means
    lower risk. Numeric features use quantile bins whose WOE is forced to be
    monotonic by merging adjacent bins; categorical features use one bin per level.
    """

    max_bins: int = 6
    min_bin_share: float = 0.05
    categorical: list = field(default_factory=list)
    edges_: dict = field(default_factory=dict, init=False)
    tables_: dict = field(default_factory=dict, init=False)

    # -- fitting -------------------------------------------------------------
    def fit(self, X: pd.DataFrame, y: pd.Series) -> "WoeBinner":
        for col in X.columns:
            if col in self.categorical:
                self.edges_[col] = None
            else:
                self.edges_[col] = self._monotonic_edges(X[col], y)
            table = self._woe_table(self._bin(X[col], col), y)
            if self.edges_[col] is not None:  # list numeric bins low -> high
                table = table.reindex([b for b in self._labels(col) if b in table.index])
            self.tables_[col] = table
        return self

    def _initial_edges(self, x: pd.Series) -> np.ndarray:
        """Quantile cut points (or every value, for low-cardinality features),
        then merge the smallest bin into a neighbour until each holds at least
        `min_bin_share` of the rows."""
        values = np.sort(x.unique())
        if len(values) <= 2 * self.max_bins:
            cuts = (values[:-1] + values[1:]) / 2
        else:
            cuts = np.unique(np.quantile(x, np.linspace(0, 1, self.max_bins + 1))[1:-1])
        edges = np.concatenate([[-np.inf], cuts, [np.inf]])
        while len(edges) > 2:
            share = pd.cut(x, edges, include_lowest=True).value_counts(sort=False).to_numpy() / len(x)
            if share.min() >= self.min_bin_share and len(edges) - 1 <= self.max_bins:
                break
            i = int(np.argmin(share))
            # drop the edge shared with the smaller neighbour
            if i == 0:
                drop = 1
            elif i == len(share) - 1:
                drop = i
            else:
                drop = i if share[i - 1] <= share[i + 1] else i + 1
            edges = np.delete(edges, drop)
        return edges

    def _monotonic_edges(self, x: pd.Series, y: pd.Series) -> np.ndarray:
        edges = self._initial_edges(x)
        while len(edges) > 3:
            bad_rate = y.groupby(pd.cut(x, edges, include_lowest=True), observed=False).mean().to_numpy()
            diffs = np.sign(np.diff(bad_rate))
            if np.all(diffs >= 0) or np.all(diffs <= 0):
                break
            # merge the adjacent pair whose bad rates are closest
            drop = np.argmin(np.abs(np.diff(bad_rate))) + 1
            edges = np.delete(edges, drop)
        return edges

    def _labels(self, col: str) -> list:
        e = self.edges_[col]
        return [f"({lo:,.6g}, {hi:,.6g}]" for lo, hi in zip(e[:-1], e[1:])]

    def _bin(self, x: pd.Series, col: str) -> pd.Series:
        edges = self.edges_[col]
        if edges is None:
            return x.astype(str)
        idx = pd.cut(x, edges, labels=False, include_lowest=True)
        return pd.Series(np.asarray(self._labels(col), dtype=object)[idx], index=x.index)

    @staticmethod
    def _woe_table(bins: pd.Series, y: pd.Series) -> pd.DataFrame:
        t = pd.DataFrame({"bin": bins.to_numpy(), "bad": y.to_numpy()})
        t = t.groupby("bin", sort=False).agg(n=("bad", "size"), bad=("bad", "sum"))
        t["good"] = t["n"] - t["bad"]
        dist_good = (t["good"] + EPS) / (t["good"].sum() + EPS * len(t))
        dist_bad = (t["bad"] + EPS) / (t["bad"].sum() + EPS * len(t))
        t["bad_rate"] = t["bad"] / t["n"]
        t["woe"] = np.log(dist_good / dist_bad)
        t["iv"] = (dist_good - dist_bad) * t["woe"]
        return t

    # -- applying ------------------------------------------------------------
    def transform(self, X: pd.DataFrame) -> pd.DataFrame:
        out = {}
        for col, table in self.tables_.items():
            bins = self._bin(X[col], col)
            # unseen categories get WOE 0 (no evidence either way)
            out[col] = bins.map(table["woe"]).fillna(0.0).astype(float)
        return pd.DataFrame(out, index=X.index)

    def information_value(self) -> pd.Series:
        return pd.Series({c: t["iv"].sum() for c, t in self.tables_.items()}).sort_values(ascending=False)


def scorecard_points(binner: WoeBinner, coefs: pd.Series, intercept: float,
                     pdo: float = 20, base_score: float = 600, base_odds: float = 50) -> pd.DataFrame:
    """Translate a logistic model on WOE features into points per bin.

    The model predicts log-odds of *default*; scores use odds of good:bad so a
    higher score means lower risk. `pdo` points double the good:bad odds, and a
    score of `base_score` corresponds to good:bad odds of `base_odds`.
    """
    factor = pdo / np.log(2)
    offset = base_score - factor * np.log(base_odds)
    n = len(coefs)
    rows = []
    for col, beta in coefs.items():
        for bin_label, r in binner.tables_[col].iterrows():
            # log-odds(good) = -(intercept + sum beta*woe); split intercept evenly
            pts = factor * (-beta * r["woe"] - intercept / n) + offset / n
            rows.append({"feature": col, "bin": bin_label, "woe": r["woe"],
                         "bad_rate": r["bad_rate"], "points": pts})
    return pd.DataFrame(rows)


def score(points: pd.DataFrame, binner: WoeBinner, X: pd.DataFrame) -> pd.Series:
    total = pd.Series(0.0, index=X.index)
    for col in points["feature"].unique():
        lookup = points.loc[points["feature"] == col].set_index("bin")["points"]
        total += binner._bin(X[col], col).map(lookup).fillna(lookup.mean()).to_numpy()
    return total
