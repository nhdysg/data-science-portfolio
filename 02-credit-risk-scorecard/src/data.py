"""Load and clean the Taiwan credit card default data, and engineer features."""

from pathlib import Path

import numpy as np
import pandas as pd

DATA_PATH = Path(__file__).resolve().parents[1] / "data" / "credit.csv"
TARGET = "default"
MONTHS = range(1, 7)  # 1 = September 2005 (most recent), 6 = April 2005

# Protected characteristics under the US Equal Credit Opportunity Act (Reg B).
# They are kept in the data for the fair-lending check but never used as features.
PROTECTED = ["SEX", "MARRIAGE", "AGE"]


def load_raw(path=DATA_PATH) -> pd.DataFrame:
    return pd.read_csv(path)


def clean(df: pd.DataFrame) -> pd.DataFrame:
    """Fix undocumented category codes.

    EDUCATION 0/5/6 and MARRIAGE 0 are not in the data dictionary; they are
    folded into the documented "other" level. Repayment status -2 (no
    consumption) and -1 (paid in full) both mean no delay, so they become 0.
    """
    out = df.copy()
    out["EDUCATION"] = out["EDUCATION"].where(out["EDUCATION"].between(1, 3), 4)
    out["MARRIAGE"] = out["MARRIAGE"].where(out["MARRIAGE"].between(1, 2), 3)
    for m in MONTHS:
        out[f"PAY_{m}"] = out[f"PAY_{m}"].clip(lower=0)
    return out


def engineer(df: pd.DataFrame) -> pd.DataFrame:
    """Add behavioural features of the kind used in card-portfolio scorecards."""
    out = df.copy()
    pay = out[[f"PAY_{m}" for m in MONTHS]]
    bill = out[[f"BILL_AMT{m}" for m in MONTHS]]
    paid = out[[f"PAY_AMT{m}" for m in MONTHS]]

    out["months_delinquent"] = (pay > 0).sum(axis=1)
    out["max_delinquency"] = pay.max(axis=1)
    out["utilization"] = (bill["BILL_AMT1"] / out["LIMIT_BAL"]).clip(-1, 3)
    out["avg_utilization"] = (bill.mean(axis=1) / out["LIMIT_BAL"]).clip(-1, 3)
    # Share of last month's bill that was paid this month; >1 means overpaid.
    prev_bill = bill[[f"BILL_AMT{m}" for m in range(2, 7)]].to_numpy()
    this_pay = paid[[f"PAY_AMT{m}" for m in range(1, 6)]].to_numpy()
    with np.errstate(divide="ignore", invalid="ignore"):
        ratio = np.where(prev_bill > 0, this_pay / prev_bill, 1.0)
    out["avg_payment_ratio"] = np.clip(ratio, 0, 2).mean(axis=1)
    out["bill_growth"] = ((bill["BILL_AMT1"] - bill["BILL_AMT6"]) / out["LIMIT_BAL"]).clip(-3, 3)
    return out


# EDUCATION is left out: it is not a protected class under ECOA, but it is a
# known proxy for protected characteristics and adds little (IV 0.045).
FEATURES = [
    "LIMIT_BAL",
    "PAY_1", "PAY_2", "PAY_3",
    "months_delinquent", "max_delinquency",
    "utilization", "avg_utilization", "avg_payment_ratio", "bill_growth",
    "PAY_AMT1", "PAY_AMT2", "BILL_AMT1",
]
CATEGORICAL: list = []


def load() -> pd.DataFrame:
    return engineer(clean(load_raw()))
