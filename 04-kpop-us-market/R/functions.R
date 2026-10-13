# Helpers for the K-pop US market analysis. Every function takes a data frame
# and returns a data frame or a model, so analysis.R only orchestrates.

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(sandwich)
  library(lmtest)
})

SEGMENT_COLORS <- c("Korean act" = "#2563EB", "KATSEYE" = "#DB2777",
                    "KPop Demon Hunters" = "#F59E0B", "Not K-pop" = "#9CA3AF")

read_processed <- function(name, dir = "data/processed") {
  d <- read.csv(file.path(dir, paste0(name, ".csv")), stringsAsFactors = FALSE)
  # DuckDB writes booleans as "True"/"False"
  is_bool <- vapply(d, function(x) all(x %in% c("True", "False", NA)), logical(1))
  d[is_bool] <- lapply(d[is_bool], function(x) x == "True")
  d
}

#' Linear model with heteroskedasticity-robust (HC3) standard errors.
#' Returns one row per coefficient with the estimate, robust 95% CI, p-value,
#' and the multiplicative effect exp(estimate) for log-outcome models.
robust_table <- function(fit, terms = NULL) {
  ct <- coeftest(fit, vcov. = vcovHC(fit, type = "HC3"))
  ci <- coefci(fit, vcov. = vcovHC(fit, type = "HC3"))
  out <- data.frame(term = rownames(ct), estimate = ct[, 1], std_error = ct[, 2],
                    conf_low = ci[, 1], conf_high = ci[, 2], p_value = ct[, 4],
                    row.names = NULL)
  out$pct_effect <- 100 * (exp(out$estimate) - 1)
  if (!is.null(terms)) out <- out[out$term %in% terms, ]
  out
}

#' Model 1: does K-pop status change how long an album stays on the chart,
#' holding its debut position and debut year fixed?
fit_album_longevity <- function(albums) {
  lm(log(weeks_first_year) ~ kpop + log(debut_pos) + factor(debut_year), data = albums)
}

#' Model 2: does the K-pop gap depend on how high the album debuted?
fit_album_longevity_interaction <- function(albums) {
  lm(log(weeks_first_year) ~ kpop * log(debut_pos) + factor(debut_year), data = albums)
}

#' Model 3: second-week retention. Outcome is log(week-2 position / debut position);
#' larger means a steeper fall. Albums that left the chart count as position 201.
fit_week2_drop <- function(albums) {
  lm(log(week2_pos / debut_pos) ~ kpop + log(debut_pos) + factor(debut_year), data = albums)
}

#' Model 4: among Korean acts' Hot 100 songs, do collaborations with
#' non-K-pop artists stay on the chart longer, holding debut position fixed?
fit_song_longevity <- function(songs) {
  lm(log(weeks_on_chart) ~ western_collab + log(debut_pos), data = songs)
}

#' Median chart position by week since debut, for each group.
trajectory_summary <- function(traj) {
  traj |>
    mutate(group = ifelse(kpop, "K-pop", "Not K-pop")) |>
    group_by(group, week_index) |>
    summarise(median_pos = median(pos), share_on_chart = mean(pos <= 200),
              albums = n(), .groups = "drop")
}
