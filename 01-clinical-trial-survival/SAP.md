# Statistical Analysis Plan

**Study:** Mayo Clinic randomized, double-blind, placebo-controlled trial of D-penicillamine in primary biliary cholangitis (PBC), 1974–1984
**Data:** `survival::pbc` (Therneau & Grambsch, 2000), first 312 records (randomized patients)
**Purpose of this document:** written before the analysis code, in the structure used for regulatory-style SAPs, so that every result in the README can be traced back to a pre-specified question.

## 1. Objectives

| | Objective | Endpoint |
|---|---|---|
| Primary | Does D-penicillamine prolong overall survival compared with placebo? | Time from randomization to death from any cause |
| Secondary | Treatment effect after adjustment for prognostic factors | Same |
| Secondary | Treatment effect on death or liver transplant | Time to death or transplant (composite) |
| Exploratory | Consistency of the treatment effect across subgroups | Same as primary |

## 2. Analysis population

**Intention-to-treat (ITT):** all 312 randomized patients, analysed by the arm they were assigned to. The 106 non-randomized patients in `pbc` are excluded.

## 3. Endpoint derivation

- Time is measured in years (days / 365.25) from registration.
- Primary: `status == 2` (death) is an event. Patients alive at last contact, or who received a liver transplant, are censored at that time.
- Composite: `status %in% c(1, 2)` is an event.
- Competing risks: transplant and death are distinct event types.

## 4. Statistical methods

### 4.1 Baseline characteristics
Summarised by arm: mean (SD) for approximately symmetric variables, median [IQR] for skewed lab values (bilirubin, alkaline phosphatase, AST), n (%) for categorical variables. Balance is described with standardized mean differences (SMD); no hypothesis tests are performed on baseline characteristics, because differences between randomized groups are due to chance by design.

### 4.2 Primary analysis
- Kaplan–Meier estimates of survival by arm with 95% CIs (log transformation), median survival, and 5- and 10-year survival.
- Two-sided **log-rank test**, α = 0.05.
- Hazard ratio from an unadjusted Cox proportional hazards model (Efron ties).

### 4.3 Covariate-adjusted analysis
Cox model adjusting for the covariates of the established Mayo PBC risk score: age (per 10 years), log2 bilirubin, log2 albumin, log2 prothrombin time, and edema (3 levels). Lab values are log-transformed based on prior knowledge of the Mayo model; this choice is checked in 4.4.

### 4.4 Model diagnostics
- **Proportional hazards:** scaled Schoenfeld residual tests and plots (`cox.zph`). If a covariate violates PH, refit with a time-varying coefficient for that covariate and report whether the treatment HR changes.
- **Functional form:** martingale residuals from a null model plotted against bilirubin on raw and log scales; AIC comparison of linear vs log bilirubin.

### 4.5 Sensitivity analyses
1. Cox model stratified by histologic stage.
2. Composite endpoint (death or transplant).
3. Competing risks: Aalen–Johansen cumulative incidence of death and transplant, and Fine–Gray subdistribution HR for death.
4. Restricted mean survival time (RMST) difference at 10 years, which does not rely on proportional hazards.

### 4.6 Subgroup analyses (exploratory)
Treatment HR within subgroups of sex, age (< 50 vs ≥ 50), bilirubin (≤ 2 vs > 2 mg/dL), and histologic stage (1–3 vs 4), with likelihood-ratio tests for the treatment-by-subgroup interaction. These are interpreted as hypothesis-generating only; no multiplicity adjustment is applied.

### 4.7 Power
Using Schoenfeld's formula, report the power the observed number of deaths gives to detect a range of hazard ratios, to put a null result in context.

## 5. Missing data
The variables used in the primary and adjusted analyses have no missing values in the ITT population. Platelet count (4 missing) is reported in Table 1 only.

## 6. Software
R (`survival`, `dplyr`, `ggplot2`, `patchwork`). All results are produced by `run_all.R`; unit tests in `tests/`.
