"""Run the full analysis: tables in output/tables, figures in output/figures."""
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

import coachella as c

HERE = Path(__file__).parent
TABLES = HERE / "output" / "tables"
FIGS = HERE / "output" / "figures"
TABLES.mkdir(parents=True, exist_ok=True)
FIGS.mkdir(parents=True, exist_ok=True)

d = c.load(HERE / "data" / "raw" / "spotify_weekly_2019_blackpink_bts.csv")

# Kill This Love came out 2019-04-05 (evening, Korea). Its first full chart week ends 04-12,
# and week 2 (ending 04-19) contains Coachella weekend 1.
# BTS "Boy With Luv" came out a week later, so its first full week ends 04-19. No Coachella.
ktl = c.retention(d, "BLACKPINK", "Kill This Love", "2019-04-12")
bwl = c.retention(d, "BTS", "Boy With Luv (feat. Halsey)", "2019-04-19")

results = []
for label, control in [("Asia", ["Asia"]), ("All non-West", ["Asia", "LatAm", "Other"])]:
    r = c.compare(ktl, bwl, control)
    r.insert(0, "control", label)
    results.append(r)
results = pd.concat(results, ignore_index=True)
results.to_csv(TABLES / "did_results.csv", index=False)
print(results.to_string(index=False))

decay = c.decay_index(d, "BLACKPINK", "Kill This Love", "2019-04-12")
decay.to_csv(TABLES / "ktl_decay_index.csv", index=False)

cat = c.catalog_by_region(d)
cat.to_csv(TABLES / "catalog_by_region.csv")
outside_asia = int(cat.drop(columns="Asia", errors="ignore").to_numpy().sum())
print(f"Catalog streams charted outside Asia in 2019: {outside_asia}")

# Figure 1: decay curves
colors = {"US": "#c2185b", "West": "#f48fb1", "Asia": "#37474f", "LatAm": "#90a4ae", "Other": "#cfd8dc"}
fig, ax = plt.subplots(figsize=(8, 4.5))
for w in c.COACHELLA_WEEKS:
    t = pd.Timestamp(w)
    ax.axvspan(t - pd.Timedelta(days=3.5), t + pd.Timedelta(days=3.5), color="#fce4ec", zorder=0)
for reg, g in decay.groupby("region"):
    ax.plot(g["week"], g["index"], marker="o", lw=2.5 if reg in ("US", "West", "Asia") else 1.2,
            color=colors[reg], label=f"{reg} ({g['countries'].iloc[0]} countries)")
ax.set_ylabel("Weekly streams (first full week = 100)")
ax.set_title("Kill This Love after release; shaded weeks contain BLACKPINK's Coachella sets")
ax.legend(frameon=False, fontsize=8)
ax.spines[["top", "right"]].set_visible(False)
fig.tight_layout()
fig.savefig(FIGS / "ktl_decay_by_region.png", dpi=150)

# Figure 2: forest plot
fig, ax = plt.subplots(figsize=(8, 3))
labels = [f"vs {r.control}: {'KTL only' if r.method == 'naive' else 'minus BTS benchmark'}" for r in results.itertuples()]
y = range(len(results))[::-1]
for yi, r in zip(y, results.itertuples()):
    col = "#c2185b" if (r.ci_low_pct > 0 or r.ci_high_pct < 0) else "#90a4ae"
    ax.plot([r.ci_low_pct, r.ci_high_pct], [yi, yi], color=col, lw=2)
    ax.plot(r.estimate_pct, yi, "o", color=col)
ax.axvline(0, color="black", lw=1)
ax.set_yticks(list(y), labels)
ax.set_xlabel("Extra week-2 retention in the West (%, 95% CI)")
ax.spines[["top", "right"]].set_visible(False)
fig.tight_layout()
fig.savefig(FIGS / "did_forest.png", dpi=150)
