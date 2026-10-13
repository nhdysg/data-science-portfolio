# Reproduce every table and figure in this project:
#   Rscript run_all.R
# Run from the 01-clinical-trial-survival/ folder.

source("R/functions.R")
suppressPackageStartupMessages(library(patchwork))

out_tab <- "output/tables"
out_fig <- "output/figures"
dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)
dir.create(out_fig, recursive = TRUE, showWarnings = FALSE)

write_table <- function(df, name, digits = 3) {
  is_p <- names(df) %in% c("p", "p_value", "p_interaction")
  df[is_p] <- lapply(df[is_p], function(p)
    ifelse(is.na(p), "", format.pval(p, digits = 2, eps = 0.001)))
  num <- vapply(df, is.numeric, logical(1)) & !names(df) %in% c("AIC", "n", "events")
  df[num] <- lapply(df[num], signif, digits = digits)
  df[] <- lapply(df, function(x) if (anyNA(x)) ifelse(is.na(x), "", x) else x)
  write.csv(df, file.path(out_tab, paste0(name, ".csv")), row.names = FALSE)
  writeLines(knitr::kable(df, format = "pipe"), file.path(out_tab, paste0(name, ".md")))
  invisible(df)
}

d <- prep_pbc()
cat("ITT population:", nrow(d), "patients,", sum(d$death), "deaths\n")

# 1. Baseline characteristics -----------------------------------------------
write_table(table_one(d), "table1_baseline")

# 2. Primary analysis: Kaplan-Meier + log-rank -------------------------------
km <- km_summary(d)
lr <- logrank_test(d)
write_table(km$medians, "km_medians")
write_table(km$landmarks, "km_landmarks")
write_table(lr, "logrank")

km_plot <- plot_km(km$fit, lr$p_value)
ggsave(file.path(out_fig, "km_overall_survival.png"),
       km_plot$curve / km_plot$risk_table + plot_layout(heights = c(4, 1)),
       width = 8, height = 6, dpi = 150, bg = "white")

# 3. Cox models --------------------------------------------------------------
cox_unadj <- fit_cox(d, Surv(years, death) ~ arm)
cox_adj   <- fit_cox(d, ADJ_FORMULA)
hr_unadj <- tidy_hr(cox_unadj)
hr_adj   <- tidy_hr(cox_adj)
write_table(hr_unadj, "cox_unadjusted")
write_table(hr_adj, "cox_adjusted")

forest_labels <- c(
  "armD-penicillamine" = "D-penicillamine vs placebo",
  "I(age/10)" = "Age (per 10 years)",
  "log2(bili)" = "Bilirubin (per doubling)",
  "log2(albumin)" = "Albumin (per doubling)",
  "log2(protime)" = "Prothrombin time (per doubling)",
  "edemaUntreated/resolved" = "Edema: untreated/resolved vs none",
  "edemaDespite diuretics" = "Edema: despite diuretics vs none"
)
hr_adj$label <- forest_labels[hr_adj$term]
ggsave(file.path(out_fig, "forest_adjusted_cox.png"),
       plot_forest(hr_adj, title = "Adjusted Cox model for death",
                   breaks = c(0.05, 0.1, 0.25, 0.5, 1, 2, 4, 8, 16, 64)),
       width = 8, height = 4, dpi = 150, bg = "white")

# 4. Model diagnostics -------------------------------------------------------
# 4a. Proportional hazards: Schoenfeld residual tests
zph <- cox.zph(cox_adj)
write_table(data.frame(term = rownames(zph$table), zph$table, row.names = NULL),
            "ph_test_schoenfeld")
png(file.path(out_fig, "schoenfeld_residuals.png"), width = 1200, height = 800, res = 150)
par(mfrow = c(2, 3), mar = c(4, 4, 2, 1))
# 1-df terms only; edema (2 df) is covered by the table above
for (i in 1:5) {
  plot(zph[i], resid = FALSE, main = rownames(zph$table)[i])
  abline(h = coef(cox_adj)[i], lty = 3, col = "red")
}
dev.off()

# 4b. Functional form of bilirubin: martingale residuals from a null model
null_fit <- coxph(Surv(years, death) ~ 1, data = d)
mart <- data.frame(bili = d$bili, resid = residuals(null_fit, type = "martingale"))
p_raw <- ggplot(mart, aes(bili, resid)) + geom_point(alpha = .4) +
  geom_smooth(method = "loess", formula = y ~ x, se = FALSE, colour = "#2563EB") +
  labs(x = "Bilirubin (mg/dL)", y = "Martingale residual", title = "Raw scale") +
  theme_minimal(base_size = 11)
p_log <- p_raw + scale_x_log10() + labs(x = "Bilirubin (mg/dL, log scale)", title = "Log scale")
ggsave(file.path(out_fig, "martingale_bilirubin.png"), p_raw + p_log,
       width = 9, height = 4, dpi = 150, bg = "white")

aic <- data.frame(
  bilirubin_form = c("linear", "log"),
  AIC = round(c(AIC(coxph(Surv(years, death) ~ bili, data = d)),
          AIC(coxph(Surv(years, death) ~ log(bili), data = d))), 1))
write_table(aic, "bilirubin_functional_form_aic")

# 5. Sensitivity and supplementary analyses ----------------------------------
fg <- fine_gray_hr(d)
composite <- tidy_hr(fit_cox(d, Surv(years, death_tx) ~ arm))
strat <- tidy_hr(fit_cox(d, Surv(years, death) ~ arm + strata(stage)))
rmst <- rmst_difference(d, tau = 10)
# Prothrombin time shows some evidence of non-proportional hazards (see 4a):
# let its log-hazard ratio change with log(time) and check the treatment HR.
cox_tt <- coxph(Surv(years, death) ~ arm + I(age / 10) + log2(bili) +
                  log2(albumin) + log2(protime) + tt(log2(protime)) + edema,
                data = d, tt = function(x, t, ...) x * log(t))
tv <- tidy_hr(cox_tt)[1, ]

sens <- rbind(
  cbind(analysis = "Primary: unadjusted Cox, death", hr_unadj),
  cbind(analysis = "Adjusted Cox (Mayo covariates)", hr_adj[1, 1:5]),
  cbind(analysis = "Adjusted Cox, time-varying prothrombin effect", tv),
  cbind(analysis = "Cox stratified by histologic stage", strat),
  cbind(analysis = "Composite: death or transplant", composite),
  cbind(analysis = "Fine-Gray: death, transplant as competing risk", fg)
)
sens$label <- sens$analysis
write_table(sens[, c("analysis", "hr", "lower", "upper", "p_value")], "sensitivity_hr")
write_table(rmst, "rmst_10y")
ggsave(file.path(out_fig, "forest_sensitivity.png"),
       plot_forest(sens, title = "Treatment effect across analyses",
                   subtitle = "HR < 1 favours D-penicillamine"),
       width = 9, height = 3.8, dpi = 150, bg = "white")

# Cumulative incidence of death vs transplant (Aalen-Johansen)
cif <- survfit(Surv(years, event_cr) ~ arm, data = d)
cif_df <- do.call(rbind, lapply(seq_along(cif$strata), function(k) {
  idx <- rep(seq_along(cif$strata), cif$strata) == k
  arm <- sub("arm=", "", names(cif$strata)[k])
  states <- cif$states
  rbind(data.frame(time = 0, arm = arm, state = c("death", "transplant"), p = 0),
        data.frame(time = rep(cif$time[idx], 2), arm = arm,
                   state = rep(c("death", "transplant"), each = sum(idx)),
                   p = c(cif$pstate[idx, which(states == "death")],
                         cif$pstate[idx, which(states == "transplant")])))
}))
ggsave(file.path(out_fig, "cumulative_incidence.png"),
       ggplot(cif_df, aes(time, p, colour = arm, linetype = state)) +
         geom_step(linewidth = 0.8) +
         scale_colour_manual(values = ARM_COLORS) +
         scale_y_continuous(labels = scales::percent) +
         labs(x = "Years since randomization", y = "Cumulative incidence",
              colour = NULL, linetype = NULL,
              title = "Death and liver transplant as competing events") +
         theme_minimal(base_size = 12) + theme(legend.position = "top"),
       width = 8, height = 5, dpi = 150, bg = "white")

# 6. Subgroup analysis -------------------------------------------------------
subgroups <- list(
  "Sex"       = function(d) d$sex,
  "Age"       = function(d) factor(ifelse(d$age < 50, "< 50", ">= 50"), levels = c("< 50", ">= 50")),
  "Bilirubin" = function(d) factor(ifelse(d$bili <= 2, "<= 2 mg/dL", "> 2 mg/dL"),
                                   levels = c("<= 2 mg/dL", "> 2 mg/dL")),
  "Stage"     = function(d) factor(ifelse(d$stage %in% c("1", "2", "3"), "1-3", "4"),
                                   levels = c("1-3", "4"))
)
sub <- subgroup_hr(d, subgroups)
write_table(sub, "subgroup_hr")
sub$label <- sprintf("%s: %s (n=%d)", sub$subgroup, sub$level, sub$n)
ggsave(file.path(out_fig, "forest_subgroups.png"),
       plot_forest(sub, title = "Treatment effect by subgroup",
                   subtitle = "HR < 1 favours D-penicillamine; see table for interaction p-values"),
       width = 8, height = 4.5, dpi = 150, bg = "white")

# 7. Power: what effect sizes could this trial detect? -----------------------
hrs <- c(0.5, 0.6, 0.7, 0.75, 0.8)
write_table(data.frame(hr = hrs,
                       power_with_observed_deaths = logrank_power(sum(d$death), hrs),
                       deaths_needed_for_80pct_power = logrank_events(hrs)),
            "power_logrank")

writeLines(capture.output(sessionInfo()), "output/sessionInfo.txt")
cat("Done. Tables in", out_tab, "| figures in", out_fig, "\n")
