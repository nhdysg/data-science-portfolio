# Data provenance

`credit.csv` is the 24,000-row modelling sample of the **Default of Credit Card Clients** data set that PyCaret distributes
(`https://raw.githubusercontent.com/pycaret/datasets/main/data/common/credit.csv`; PyCaret holds back the other 6,000 rows of the original 30,000).

- Original source: UCI Machine Learning Repository, https://archive.ics.uci.edu/dataset/350/default+of+credit+card+clients (CC BY 4.0)
- Citation: Yeh, I. C., & Lien, C. H. (2009). The comparisons of data mining techniques for the predictive accuracy of probability of default of credit card clients. *Expert Systems with Applications*, 36(2), 2473–2480.
- SHA-256: `0f2c8fcc66e1f90e5fa79b92df18c0a67f8c7c4ec1eabbc4fd256438bcc608bf`
- Checks: 24,000 rows, 24 columns, no missing values, default rate 22.1% (UCI full data: 22.1%). 24 rows are exact duplicates and are kept, as they may be distinct customers.

Column naming follows PyCaret: `PAY_1` is the September 2005 repayment status (`PAY_0` in the UCI file), and `default` is the target (`default payment next month`).
