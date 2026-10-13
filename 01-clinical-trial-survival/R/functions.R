# Analysis functions for the Mayo PBC D-penicillamine trial.
# Every function takes a data frame and returns a data frame or model object,
# so run_all.R only orchestrates and writes outputs.

suppressPackageStartupMessages({
  library(survival)
  library(dplyr)
  library(ggplot2)
})

DAYS_PER_YEAR <- 365.25

# ---- Data ------------------------------------------------------------------

#' Build the analysis data set (ITT population: the 312 randomized patients).
#'
#' Endpoints
#'   death      primary: death from any cause; transplant and alive = censored
#'   death_tx   sensitivity: death or liver transplant (composite)
#'   event_cr   competing-risks coding: 0 censored, 1 transplant, 2 death
prep_pbc <- function(raw = survival::pbc) {
  raw |>
    filter(!is.na(trt)) |>
    transmute(
      id,
      years    = time / DAYS_PER_YEAR,
      death    = as.integer(status == 2),
      death_tx = as.integer(status %in% c(1, 2)),
      event_cr = factor(status, levels = c(0, 1, 2),
                        labels = c("censored", "transplant", "death")),
      arm      = factor(trt, levels = c(2, 1),
                        labels = c("Placebo", "D-penicillamine")),
      age,
      sex      = factor(sex, levels = c("m", "f"), labels = c("Male", "Female")),
      edema    = factor(edema, levels = c(0, 0.5, 1),
                        labels = c("None", "Untreated/resolved", "Despite diuretics")),
      ascites  = factor(ascites, levels = 0:1, labels = c("No", "Yes")),
      stage    = factor(stage),
      bili, albumin, protime, alk.phos, ast, platelet
    )
}

# ---- Table 1 ---------------------------------------------------------------

fmt_num <- function(x, digits = 1) formatC(x, format = "f", digits = digits)

# Standardized mean difference for a continuous variable (pooled SD).
smd_continuous <- function(x, g) {
  lv <- levels(g)
  a <- x[g == lv[1]]; b <- x[g == lv[2]]
  (mean(b, na.rm = TRUE) - mean(a, na.rm = TRUE)) /
    sqrt((var(a, na.rm = TRUE) + var(b, na.rm = TRUE)) / 2)
}

# Multi-level SMD for a categorical variable (Yang & Dalton 2012).
smd_categorical <- function(x, g) {
  lv <- levels(g)
  p1 <- prop.table(table(x[g == lv[1]]))
  p2 <- prop.table(table(x[g == lv[2]]))
  k <- length(p1)
  if (k < 2) return(NA_real_)
  t <- (p2 - p1)[-1]
  S <- matrix(0, k - 1, k - 1)
  for (i in seq_len(k - 1)) for (j in seq_len(k - 1)) {
    pi1 <- p1[i + 1]; pj1 <- p1[j + 1]; pi2 <- p2[i + 1]; pj2 <- p2[j + 1]
    S[i, j] <- if (i == j) (pi1 * (1 - pi1) + pi2 * (1 - pi2)) / 2
               else -(pi1 * pj1 + pi2 * pj2) / 2
  }
  sqrt(as.numeric(t %*% solve(S) %*% t))
}

#' Baseline characteristics by arm with standardized mean differences.
#' `skewed` variables are summarised as median [IQR], others as mean (SD).
table_one <- function(d, group = "arm",
                      continuous = c("age", "bili", "albumin", "protime",
                                     "alk.phos", "ast", "platelet"),
                      skewed = c("bili", "alk.phos", "ast"),
                      categorical = c("sex", "edema", "ascites", "stage")) {
  g <- d[[group]]
  lv <- levels(g)
  header <- paste0(lv, " (n=", as.vector(table(g)), ")")

  cont_rows <- lapply(continuous, function(v) {
    x <- d[[v]]
    summ <- vapply(lv, function(l) {
      xi <- x[g == l]
      if (v %in% skewed) {
        q <- quantile(xi, c(.25, .5, .75), na.rm = TRUE)
        sprintf("%s [%s, %s]", fmt_num(q[2]), fmt_num(q[1]), fmt_num(q[3]))
      } else {
        sprintf("%s (%s)", fmt_num(mean(xi, na.rm = TRUE)), fmt_num(sd(xi, na.rm = TRUE)))
      }
    }, character(1))
    stat <- if (v %in% skewed) "median [IQR]" else "mean (SD)"
    data.frame(variable = paste0(v, ", ", stat), level = "",
               a = summ[1], b = summ[2],
               smd = fmt_num(abs(smd_continuous(x, g)), 2),
               missing = sum(is.na(x)))
  })

  cat_rows <- lapply(categorical, function(v) {
    x <- d[[v]]
    tab <- table(x, g)
    pct <- prop.table(tab, 2) * 100
    cells <- matrix(sprintf("%d (%s%%)", tab, fmt_num(pct)), nrow = nrow(tab))
    data.frame(variable = c(paste0(v, ", n (%)"), rep("", nrow(tab) - 1)),
               level = rownames(tab), a = cells[, 1], b = cells[, 2],
               smd = c(fmt_num(smd_categorical(x, g), 2), rep("", nrow(tab) - 1)),
               missing = c(sum(is.na(x)), rep(NA, nrow(tab) - 1)))
  })

  out <- do.call(rbind, c(cont_rows, cat_rows))
  names(out) <- c("Variable", "Level", header, "SMD", "Missing")
  rownames(out) <- NULL
  out
}

# ---- Survival summaries ----------------------------------------------------

#' Kaplan-Meier fit plus a tidy summary: median survival and
#' landmark survival probabilities (with 95% CI) per arm.
km_summary <- function(d, times = c(5, 10)) {
  fit <- survfit(Surv(years, death) ~ arm, data = d)
  s <- summary(fit, times = times, extend = TRUE)
  landmarks <- data.frame(
    arm = sub("arm=", "", s$strata), year = s$time,
    surv = s$surv, lower = s$lower, upper = s$upper
  )
  medians <- data.frame(arm = sub("arm=", "", rownames(summary(fit)$table)),
                        median_years = summary(fit)$table[, "median"],
                        events = summary(fit)$table[, "events"],
                        n = summary(fit)$table[, "n.max"])
  rownames(medians) <- NULL
  list(fit = fit, landmarks = landmarks, medians = medians)
}

logrank_test <- function(d, formula = Surv(years, death) ~ arm) {
  lr <- survdiff(formula, data = d)
  df <- length(lr$n) - 1
  data.frame(chisq = unname(lr$chisq), df = df,
             p_value = pchisq(lr$chisq, df, lower.tail = FALSE))
}

#' Restricted mean survival time difference up to `tau` years.
#' Arms are independent, so SE of the difference is sqrt(se1^2 + se2^2).
rmst_difference <- function(d, tau = 10) {
  fit <- survfit(Surv(years, death) ~ arm, data = d)
  tab <- summary(fit, rmean = tau)$table
  est <- tab[, "rmean"]; se <- tab[, "se(rmean)"]
  diff <- unname(est[2] - est[1])
  se_diff <- sqrt(sum(se^2))
  data.frame(tau_years = tau,
             rmst_placebo = unname(est[1]), rmst_dpca = unname(est[2]),
             difference = diff,
             lower = diff - qnorm(.975) * se_diff,
             upper = diff + qnorm(.975) * se_diff,
             p_value = 2 * pnorm(-abs(diff / se_diff)))
}

# ---- Cox models ------------------------------------------------------------

# Pre-specified adjustment set: the covariates of the Mayo PBC risk score.
# Lab values enter on the log2 scale (HR per doubling), age per 10 years.
ADJ_FORMULA <- Surv(years, death) ~ arm + I(age / 10) + log2(bili) +
  log2(albumin) + log2(protime) + edema

fit_cox <- function(d, formula) coxph(formula, data = d)

#' Hazard ratios with 95% CI from a coxph fit.
tidy_hr <- function(fit) {
  s <- summary(fit)
  ci <- s$conf.int
  data.frame(term = rownames(ci), hr = ci[, "exp(coef)"],
             lower = ci[, "lower .95"], upper = ci[, "upper .95"],
             p_value = s$coefficients[, "Pr(>|z|)"], row.names = NULL)
}

#' Treatment HR within each subgroup plus the treatment-by-subgroup
#' interaction p-value (likelihood ratio test).
subgroup_hr <- function(d, subgroups) {
  rows <- lapply(names(subgroups), function(nm) {
    g <- subgroups[[nm]](d)
    d2 <- d; d2$.sub <- g
    within <- lapply(levels(g), function(l) {
      di <- d2[d2$.sub == l, ]
      f <- coxph(Surv(years, death) ~ arm, data = di)
      h <- tidy_hr(f)
      data.frame(subgroup = nm, level = l, n = nrow(di), events = sum(di$death),
                 hr = h$hr, lower = h$lower, upper = h$upper)
    })
    m0 <- coxph(Surv(years, death) ~ arm + .sub, data = d2)
    m1 <- coxph(Surv(years, death) ~ arm * .sub, data = d2)
    p_int <- anova(m0, m1)[["Pr(>|Chi|)"]][2]
    out <- do.call(rbind, within)
    out$p_interaction <- c(p_int, rep(NA, nrow(out) - 1))
    out
  })
  do.call(rbind, rows)
}

#' Fine-Gray subdistribution HR for death, treating transplant as competing.
fine_gray_hr <- function(d) {
  fg <- finegray(Surv(years, event_cr) ~ ., data = d, etype = "death")
  fit <- coxph(Surv(fgstart, fgstop, fgstatus) ~ arm, weights = fgwt, data = fg)
  tidy_hr(fit)
}

# ---- Plots -----------------------------------------------------------------

ARM_COLORS <- c("Placebo" = "#6B7280", "D-penicillamine" = "#2563EB")

#' Kaplan-Meier curves with step-shaped 95% CI bands and censoring marks,
#' plus a separate numbers-at-risk panel (combined in run_all.R).
plot_km <- function(km_fit, lr_p, break_years = seq(0, 12, 2)) {
  arms <- sub("arm=", "", names(km_fit$strata))
  curves <- data.frame(time = km_fit$time, surv = km_fit$surv,
                       lower = km_fit$lower, upper = km_fit$upper,
                       n.censor = km_fit$n.censor,
                       arm = rep(arms, km_fit$strata))
  curves <- rbind(data.frame(time = 0, surv = 1, lower = 1, upper = 1,
                             n.censor = 0, arm = arms), curves)
  curves <- curves[order(curves$arm, curves$time), ]

  # Duplicate each point at the next time so the ribbon follows the steps.
  band <- do.call(rbind, lapply(split(curves, curves$arm), function(c) {
    nxt <- c(c$time[-1], c$time[nrow(c)])
    data.frame(arm = c$arm[1], time = c(rbind(c$time, nxt)),
               lower = rep(c$lower, each = 2), upper = rep(c$upper, each = 2))
  }))

  curve <- ggplot(curves, aes(time, surv, colour = arm)) +
    geom_ribbon(data = band, aes(x = time, ymin = lower, ymax = upper, fill = arm),
                inherit.aes = FALSE, alpha = 0.12) +
    geom_step(linewidth = 0.8) +
    geom_point(data = subset(curves, n.censor > 0), shape = 3, size = 1.5) +
    scale_colour_manual(values = ARM_COLORS) +
    scale_fill_manual(values = ARM_COLORS, guide = "none") +
    scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
    coord_cartesian(xlim = range(break_years)) +
    scale_x_continuous(breaks = break_years) +
    annotate("text", x = 0.3, y = 0.08, hjust = 0,
             label = sprintf("Log-rank p = %.2f", lr_p)) +
    labs(x = "Years since randomization", y = "Overall survival", colour = NULL,
         title = "Overall survival by treatment arm (ITT, n = 312)") +
    theme_minimal(base_size = 12) +
    theme(legend.position = "top", panel.grid.minor = element_blank())

  risk <- summary(km_fit, times = break_years, extend = TRUE)
  risk_df <- data.frame(time = risk$time, n = risk$n.risk,
                        arm = factor(sub("arm=", "", risk$strata), levels = rev(arms)))
  risk_table <- ggplot(risk_df, aes(time, arm, label = n, colour = arm)) +
    geom_text(size = 3.5) +
    scale_colour_manual(values = ARM_COLORS, guide = "none") +
    coord_cartesian(xlim = range(break_years)) +
    scale_x_continuous(breaks = break_years) +
    labs(x = NULL, y = NULL, subtitle = "Number at risk") +
    theme_minimal(base_size = 11) +
    theme(panel.grid = element_blank(), axis.text.x = element_blank())

  list(curve = curve, risk_table = risk_table)
}

#' Forest plot: one row per term or subgroup, HR on a log scale.
plot_forest <- function(df, label_col = "label", title = NULL, subtitle = NULL,
                        breaks = c(0.25, 0.5, 0.75, 1, 1.5, 2, 3)) {
  df$label <- factor(df[[label_col]], levels = rev(unique(df[[label_col]])))
  ggplot(df, aes(hr, label)) +
    geom_vline(xintercept = 1, linetype = "dashed", colour = "grey50") +
    geom_errorbarh(aes(xmin = lower, xmax = upper), height = 0.2) +
    geom_point(size = 2.5, colour = "#2563EB") +
    scale_x_log10(breaks = breaks) +
    labs(x = "Hazard ratio (95% CI, log scale)", y = NULL,
         title = title, subtitle = subtitle) +
    theme_minimal(base_size = 12) +
    theme(panel.grid.minor = element_blank())
}

# ---- Power -----------------------------------------------------------------

#' Power of a two-sided log-rank test with 1:1 allocation (Schoenfeld 1981).
logrank_power <- function(events, hr, alpha = 0.05) {
  pnorm(sqrt(events / 4) * abs(log(hr)) - qnorm(1 - alpha / 2))
}

#' Events required for a given power (Schoenfeld 1981).
logrank_events <- function(hr, power = 0.8, alpha = 0.05) {
  ceiling(4 * (qnorm(1 - alpha / 2) + qnorm(power))^2 / log(hr)^2)
}
