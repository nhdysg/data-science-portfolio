"""Reproduce every table and figure:  python run_all.py  (from this folder)."""

from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import xgboost as xgb
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_curve
from sklearn.model_selection import GridSearchCV, StratifiedKFold, train_test_split

from src import data, metrics
from src.woe import WoeBinner, score, scorecard_points

SEED = 42
OUT = Path("output")
TAB, FIG = OUT / "tables", OUT / "figures"
TAB.mkdir(parents=True, exist_ok=True)
FIG.mkdir(parents=True, exist_ok=True)
BLUE, GREY, RED = "#2563EB", "#6B7280", "#DC2626"
plt.rcParams.update({"figure.dpi": 150, "axes.spines.top": False, "axes.spines.right": False,
                     "axes.grid": True, "grid.alpha": 0.3, "font.size": 10})


def save_table(df: pd.DataFrame, name: str, digits: int = 3) -> pd.DataFrame:
    df = df.copy()
    num = df.select_dtypes("number").columns
    df[num] = df[num].round(digits)
    df.to_csv(TAB / f"{name}.csv", index=False)
    (TAB / f"{name}.md").write_text(df.to_markdown(index=False) + "\n")
    return df


# 1. Data ---------------------------------------------------------------------
df = data.load()
X, y = df[data.FEATURES], df[data.TARGET]
X_tr, X_te, y_tr, y_te, prot_tr, prot_te = train_test_split(
    X, y, df[data.PROTECTED], test_size=0.3, stratify=y, random_state=SEED)
print(f"{len(df):,} accounts, default rate {y.mean():.1%}; train {len(X_tr):,} / test {len(X_te):,}")
save_table(pd.DataFrame({
    "split": ["train", "test"], "accounts": [len(y_tr), len(y_te)],
    "defaults": [y_tr.sum(), y_te.sum()], "default_rate": [y_tr.mean(), y_te.mean()]}), "split_summary")

# 2. WOE scorecard ------------------------------------------------------------
binner = WoeBinner(categorical=data.CATEGORICAL).fit(X_tr, y_tr)
iv = binner.information_value().rename_axis("feature").reset_index(name="iv")
iv["strength"] = pd.cut(iv["iv"], [-np.inf, 0.02, 0.1, 0.3, 0.5, np.inf],
                        labels=["unpredictive", "weak", "medium", "strong", "very strong"])

# Keep features with IV >= 0.02, then drop any whose coefficient has the wrong
# sign (positive on WOE means "lower risk bin -> higher default"), which signals
# collinearity rather than a real effect. Refit until all signs are negative.
# Among WOE features correlated above 0.7, keep only the one with the higher IV.
W_tr, W_te = binner.transform(X_tr), binner.transform(X_te)
selected = []
for f in iv.loc[iv["iv"] >= 0.02, "feature"]:  # already sorted by IV, high to low
    if all(abs(W_tr[f].corr(W_tr[g])) <= 0.7 for g in selected):
        selected.append(f)
decision = {f: "dropped: correlated > 0.7 with a higher-IV feature"
            for f in iv.loc[iv["iv"] >= 0.02, "feature"] if f not in selected}
decision.update({f: "dropped: IV < 0.02" for f in iv.loc[iv["iv"] < 0.02, "feature"]})
while True:
    logit = LogisticRegression(C=1e6, max_iter=1000).fit(W_tr[selected], y_tr)
    coefs = pd.Series(logit.coef_[0], index=selected)
    if (coefs < 0).all():
        break
    decision[coefs.idxmax()] = "dropped: wrong-sign coefficient (collinearity)"
    selected.remove(coefs.idxmax())
decision.update({f: "kept" for f in selected})
iv["decision"] = iv["feature"].map(decision)
save_table(iv, "feature_selection")
save_table(coefs.rename_axis("feature").reset_index(name="coefficient"), "scorecard_coefficients")

points = scorecard_points(binner, coefs, logit.intercept_[0])
save_table(points, "scorecard_points", digits=2)
score_tr = score(points, binner, X_tr)
score_te = score(points, binner, X_te)
p_sc_tr = logit.predict_proba(W_tr[selected])[:, 1]
p_sc_te = logit.predict_proba(W_te[selected])[:, 1]

# 3. Gradient boosting challenger --------------------------------------------
grid = GridSearchCV(
    xgb.XGBClassifier(learning_rate=0.05, subsample=0.8, colsample_bytree=0.8,
                      eval_metric="auc", random_state=SEED, n_jobs=4),
    {"max_depth": [2, 3, 4], "n_estimators": [200, 400], "min_child_weight": [1, 10]},
    scoring="roc_auc", cv=StratifiedKFold(5, shuffle=True, random_state=SEED), n_jobs=1)
grid.fit(X_tr, y_tr)
gbm = grid.best_estimator_
save_table(pd.DataFrame([{**grid.best_params_, "cv_auc": grid.best_score_}]), "xgb_best_params")
p_gb_tr = gbm.predict_proba(X_tr)[:, 1]
p_gb_te = gbm.predict_proba(X_te)[:, 1]

# 4. Performance --------------------------------------------------------------
perf = pd.DataFrame([
    {**metrics.summarize("Scorecard (WOE logistic)", y_tr, p_sc_tr), "sample": "train"},
    {**metrics.summarize("Scorecard (WOE logistic)", y_te, p_sc_te), "sample": "test"},
    {**metrics.summarize("XGBoost", y_tr, p_gb_tr), "sample": "train"},
    {**metrics.summarize("XGBoost", y_te, p_gb_te), "sample": "test"},
])
save_table(perf[["model", "sample", "auc", "gini", "ks", "brier"]], "performance")
save_table(pd.DataFrame({"score": ["scorecard points", "XGBoost PD"],
                         "psi_train_vs_test": [metrics.psi(score_tr, score_te),
                                               metrics.psi(p_gb_tr, p_gb_te)]}), "stability_psi", 4)
save_table(metrics.decile_table(y_te, p_sc_te), "decile_scorecard_test")
save_table(metrics.decile_table(y_te, p_gb_te), "decile_xgb_test")

fig, ax = plt.subplots(figsize=(5.5, 5))
for name, p, c in [("Scorecard", p_sc_te, BLUE), ("XGBoost", p_gb_te, RED)]:
    fpr, tpr, _ = roc_curve(y_te, p)
    auc = metrics.roc_auc_score(y_te, p)
    ax.plot(fpr, tpr, color=c, label=f"{name} (AUC {auc:.3f})")
ax.plot([0, 1], [0, 1], ls="--", color=GREY, lw=1)
ax.set(xlabel="False positive rate", ylabel="True positive rate", title="ROC curve, test set")
ax.legend(loc="lower right")
fig.tight_layout(); fig.savefig(FIG / "roc_test.png"); plt.close(fig)

# KS plot for the scorecard
fig, ax = plt.subplots(figsize=(6.5, 4.5))
s = np.sort(score_te.to_numpy())
bad = np.sort(score_te[y_te.to_numpy() == 1].to_numpy())
good = np.sort(score_te[y_te.to_numpy() == 0].to_numpy())
cdf_bad = np.searchsorted(bad, s, side="right") / len(bad)
cdf_good = np.searchsorted(good, s, side="right") / len(good)
i = np.argmax(cdf_bad - cdf_good)
ax.plot(s, cdf_bad, color=RED, label="Defaulters")
ax.plot(s, cdf_good, color=BLUE, label="Non-defaulters")
ax.vlines(s[i], cdf_good[i], cdf_bad[i], color="black", ls=":")
ax.annotate(f"KS = {cdf_bad[i] - cdf_good[i]:.2f}\nat score {s[i]:.0f}", (s[i], (cdf_bad[i] + cdf_good[i]) / 2),
            xytext=(10, 0), textcoords="offset points", va="center")
ax.set(xlabel="Scorecard points (higher = lower risk)", ylabel="Cumulative share",
       title="Kolmogorov-Smirnov separation, test set")
ax.legend(loc="lower right")
fig.tight_layout(); fig.savefig(FIG / "ks_scorecard.png"); plt.close(fig)

# Calibration
fig, ax = plt.subplots(figsize=(5.5, 5))
for name, p, c in [("Scorecard", p_sc_te, BLUE), ("XGBoost", p_gb_te, RED)]:
    cal = metrics.calibration_table(y_te, p)
    ax.plot(cal["predicted"], cal["observed"], "o-", color=c, label=name)
ax.plot([0, 0.8], [0, 0.8], ls="--", color=GREY, lw=1)
ax.set(xlabel="Predicted default probability (decile mean)", ylabel="Observed default rate",
       title="Calibration, test set")
ax.legend()
fig.tight_layout(); fig.savefig(FIG / "calibration_test.png"); plt.close(fig)

# 5. Explainability -------------------------------------------------------------
contribs = gbm.get_booster().predict(xgb.DMatrix(X_te), pred_contribs=True)[:, :-1]
shap_imp = pd.DataFrame({"feature": data.FEATURES,
                         "mean_abs_shap": np.abs(contribs).mean(axis=0)}).sort_values("mean_abs_shap")
save_table(shap_imp.sort_values("mean_abs_shap", ascending=False), "xgb_shap_importance", 4)
fig, ax = plt.subplots(figsize=(6.5, 4.5))
ax.barh(shap_imp["feature"], shap_imp["mean_abs_shap"], color=BLUE)
ax.set(xlabel="Mean |SHAP value| (log-odds)", title="What drives the XGBoost prediction")
fig.tight_layout(); fig.savefig(FIG / "xgb_shap_importance.png"); plt.close(fig)

# 6. Business use: collections prioritisation --------------------------------
# Assumptions: exposure at default = current statement balance (floored at 0);
# loss given default 75%; the collections team can work a fixed share of accounts.
LGD = 0.75
ead = X_te["BILL_AMT1"].clip(lower=0).to_numpy()
loss = y_te.to_numpy() * ead * LGD
rows = []
for share in [0.05, 0.10, 0.20, 0.30]:
    k = int(round(share * len(y_te)))
    for name, p in [("Scorecard", p_sc_te), ("XGBoost", p_gb_te)]:
        top = np.argsort(-p)[:k]
        rows.append({"accounts_worked": f"{share:.0%}", "model": name,
                     "defaults_captured": y_te.to_numpy()[top].sum() / y_te.sum(),
                     "loss_captured": loss[top].sum() / loss.sum(),
                     "precision": y_te.to_numpy()[top].mean()})
    rows.append({"accounts_worked": f"{share:.0%}", "model": "Random",
                 "defaults_captured": share, "loss_captured": share, "precision": y_te.mean()})
capture = save_table(pd.DataFrame(rows), "collections_capture")

fig, ax = plt.subplots(figsize=(6, 4.5))
grid_x = np.linspace(0, 1, 101)
for name, p, c in [("Scorecard", p_sc_te, BLUE), ("XGBoost", p_gb_te, RED)]:
    order = np.argsort(-p)
    cum = np.r_[0, np.cumsum(y_te.to_numpy()[order])] / y_te.sum()
    ax.plot(np.linspace(0, 1, len(cum)), cum, color=c, label=name)
ax.plot(grid_x, grid_x, ls="--", color=GREY, lw=1, label="Random")
ax.axvline(0.2, color="black", ls=":", lw=1)
ax.set(xlabel="Share of accounts worked (highest predicted risk first)",
       ylabel="Share of next-month defaults captured", title="Cumulative gains, test set")
ax.legend(loc="lower right")
fig.tight_layout(); fig.savefig(FIG / "gains_test.png"); plt.close(fig)

# 7. Fair-lending check --------------------------------------------------------
# Flag the riskiest 20% (scorecard) for adverse action and compare outcomes across
# protected groups. Adverse impact ratio (AIR) = a group's favourable-outcome rate
# (not flagged) / the highest favourable rate in that attribute; below 0.8 (the
# "four-fifths rule") would warrant review.
flag = pd.Series(p_sc_te >= np.quantile(p_sc_te, 0.8), index=X_te.index)
groups = {
    "sex": prot_te["SEX"].map({1: "Male", 2: "Female"}),
    "age": pd.cut(prot_te["AGE"], [0, 30, 45, 120], labels=["< 30", "30-44", "45+"]),
}
fair = []
for g, labels in groups.items():
    t = pd.DataFrame({"group": labels, "flag": flag, "default": y_te}).groupby("group", observed=True)
    rates = t.agg(accounts=("flag", "size"), flag_rate=("flag", "mean"), default_rate=("default", "mean"))
    rates["adverse_impact_ratio"] = (1 - rates["flag_rate"]) / (1 - rates["flag_rate"]).max()
    rates.insert(0, "attribute", g)
    fair.append(rates.reset_index())
save_table(pd.concat(fair), "fair_lending_check")

print(perf.to_string(index=False))
print(capture.to_string(index=False))
print("Done.")
