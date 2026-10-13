# Regression analysis and figures:  Rscript analysis.R
# Run `python build.py` first to create data/processed/.

source("R/functions.R")
suppressPackageStartupMessages({
  library(ggrepel)
  library(scales)
})

out_tab <- "output/tables"
out_fig <- "output/figures"
dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)
dir.create(out_fig, recursive = TRUE, showWarnings = FALSE)
theme_set(theme_minimal(base_size = 12) +
            theme(panel.grid.minor = element_blank(), legend.position = "top"))

write_table <- function(df, name, digits = 3) {
  # round measurements to 3 significant digits but leave counts untouched
  num <- vapply(df, function(x) is.numeric(x) && any(x != round(x), na.rm = TRUE), logical(1))
  df[num] <- lapply(df[num], function(x) signif(x, digits))
  write.csv(df, file.path(out_tab, paste0(name, ".csv")), row.names = FALSE)
  writeLines(knitr::kable(df, format = "pipe"), file.path(out_tab, paste0(name, ".md")))
  invisible(df)
}

yearly <- read_processed("yearly_presence")
albums <- read_processed("albums")
traj   <- read_processed("album_trajectories")
songs  <- read_processed("kpop_songs")
acts   <- read_processed("act_balance")

# 1. Growth on the charts -------------------------------------------------------
yearly$chart_label <- ifelse(yearly$chart == "hot100", "Hot 100 (songs)", "Billboard 200 (albums)")
latest_week <- max(as.Date(songs$debut_week))
p <- ggplot(yearly, aes(year, kpop_share_pct, colour = chart_label)) +
  geom_line(linewidth = 1) + geom_point(size = 1.8) +
  annotate("text", x = 2012, y = 0.9, label = "PSY\n'Gangnam Style'", size = 3, hjust = 0.5) +
  annotate("text", x = 2020, y = 2.1, label = "BTS\n'Dynamite'", size = 3, hjust = 0.5) +
  annotate("text", x = 2024.4, y = 5.6, label = "KPop Demon\nHunters", size = 3, hjust = 1) +
  scale_colour_manual(values = c("Hot 100 (songs)" = "#F59E0B", "Billboard 200 (albums)" = "#2563EB")) +
  scale_x_continuous(breaks = seq(2009, 2026, 2)) +
  labs(x = NULL, y = "Share of chart slots held by K-pop (%)", colour = NULL,
       title = "K-pop's share of the US charts, 2009-2026",
       caption = "2026 runs to mid-October.")
ggsave(file.path(out_fig, "kpop_share_by_year.png"), p, width = 8, height = 4.8, dpi = 150, bg = "white")

# 2. Album longevity ------------------------------------------------------------
m1 <- fit_album_longevity(albums)
m2 <- fit_album_longevity_interaction(albums)
m3 <- fit_week2_drop(albums)
models <- rbind(
  cbind(model = "1. log(weeks in first year)", robust_table(m1, c("kpopTRUE", "log(debut_pos)"))),
  cbind(model = "2. ... with interaction", robust_table(m2, c("kpopTRUE", "log(debut_pos)", "kpopTRUE:log(debut_pos)"))),
  cbind(model = "3. log(week-2 pos / debut pos)", robust_table(m3, c("kpopTRUE", "log(debut_pos)")))
)
write_table(models, "album_models")
write_table(data.frame(model = c("1", "2", "3"),
                       n = c(nobs(m1), nobs(m2), nobs(m3)),
                       kpop_albums = sum(albums$kpop),
                       r_squared = c(summary(m1)$r.squared, summary(m2)$r.squared, summary(m3)$r.squared)),
            "album_models_fit")

album_summary <- albums |>
  mutate(group = ifelse(kpop, "K-pop", "Not K-pop")) |>
  group_by(group) |>
  summarise(albums = n(),
            median_debut_pos = median(debut_pos),
            share_debut_no1 = mean(debut_pos == 1),
            median_week2_pos = median(week2_pos),
            share_off_chart_week2 = mean(off_chart_week2),
            median_weeks_first_year = median(weeks_first_year),
            .groups = "drop")
write_table(album_summary, "album_summary")

# Matched comparison: albums that debuted in the top 5
top5 <- albums |>
  filter(debut_pos <= 5) |>
  mutate(group = ifelse(kpop, "K-pop", "Not K-pop")) |>
  group_by(group) |>
  summarise(albums = n(), median_weeks_first_year = median(weeks_first_year),
            share_still_charting_week5 = NA_real_, .groups = "drop")
wk5 <- traj |> filter(week_index == 4) |>
  mutate(group = ifelse(kpop, "K-pop", "Not K-pop")) |>
  semi_join(albums |> filter(debut_pos <= 5), by = c("title", "performer")) |>
  group_by(group) |> summarise(share = mean(pos <= 200), .groups = "drop")
top5$share_still_charting_week5 <- wk5$share[match(top5$group, wk5$group)]
write_table(top5, "top5_debuts")

ts <- trajectory_summary(traj)
write_table(ts, "album_trajectories_summary")
p <- ggplot(ts, aes(week_index + 1, median_pos, colour = group)) +
  geom_line(linewidth = 1) + geom_point(size = 1.8) +
  scale_y_reverse(breaks = c(1, 25, 50, 100, 150, 200)) +
  scale_x_continuous(breaks = 1:13) +
  scale_colour_manual(values = c("K-pop" = "#2563EB", "Not K-pop" = "#9CA3AF")) +
  labs(x = "Week on chart", y = "Median Billboard 200 position\n(201 = off the chart)", colour = NULL,
       title = "Top-10 album debuts: K-pop falls off a cliff",
       subtitle = sprintf("Albums debuting in the top 10, 2018-2025 (K-pop n = %d, other n = %d)",
                          sum(ts$albums[ts$group == "K-pop" & ts$week_index == 0]),
                          sum(ts$albums[ts$group == "Not K-pop" & ts$week_index == 0])))
ggsave(file.path(out_fig, "album_trajectories.png"), p, width = 8, height = 5, dpi = 150, bg = "white")

p <- ggplot(albums, aes(debut_pos, weeks_first_year, colour = ifelse(kpop, "K-pop", "Not K-pop"))) +
  geom_jitter(data = subset(albums, !kpop), alpha = 0.25, width = 0.03, height = 0.03, size = 1.2) +
  geom_jitter(data = subset(albums, kpop), alpha = 0.8, width = 0.03, height = 0.03, size = 1.6) +
  geom_smooth(method = "lm", formula = y ~ x, se = TRUE) +
  scale_x_log10(breaks = c(1, 2, 5, 10, 20, 50)) +
  scale_y_log10(breaks = c(1, 2, 5, 10, 20, 52)) +
  scale_colour_manual(values = c("K-pop" = "#2563EB", "Not K-pop" = "#9CA3AF")) +
  labs(x = "Debut position (log scale)", y = "Weeks on chart in first year (log scale)", colour = NULL,
       title = "At any debut position, K-pop albums chart for fewer weeks")
ggsave(file.path(out_fig, "album_longevity_scatter.png"), p, width = 8, height = 5, dpi = 150, bg = "white")

png(file.path(out_fig, "model1_diagnostics.png"), width = 1200, height = 600, res = 150)
par(mfrow = c(1, 2), mar = c(4, 4, 2, 1))
plot(m1, which = 1, caption = "", main = "Residuals vs fitted")
plot(m1, which = 2, caption = "", main = "Normal Q-Q")
dev.off()

# 3. Songs: what crosses over? -----------------------------------------------------
korean_songs <- subset(songs, segment == "Korean act" & !still_charting)
m4 <- fit_song_longevity(korean_songs)
write_table(cbind(model = "4. log(weeks on Hot 100)", robust_table(m4, c("western_collabTRUE", "log(debut_pos)"))),
            "song_model")
song_summary <- songs |>
  mutate(group = case_when(segment != "Korean act" ~ segment,
                           western_collab ~ "Korean act + Western artist",
                           TRUE ~ "Korean act alone")) |>
  group_by(group) |>
  summarise(songs = n(), median_weeks = median(weeks_on_chart), mean_weeks = mean(weeks_on_chart),
            share_one_week = mean(weeks_on_chart == 1), top10_hits = sum(peak_pos <= 10),
            .groups = "drop") |>
  arrange(desc(mean_weeks))
write_table(song_summary, "song_summary")
write_table(head(songs[, c("title", "performer", "segment", "debut_year", "peak_pos", "weeks_on_chart")], 15),
            "top_kpop_songs")

# 4. Album-led vs song-led acts -----------------------------------------------------
acts$segment_label <- c(korean = "Korean act", us_made = "KATSEYE", kdh = "KPop Demon Hunters")[acts$segment]
plot_acts <- subset(acts, album_chart_weeks + song_chart_weeks >= 20)
p <- ggplot(plot_acts, aes(album_chart_weeks + 1, song_chart_weeks + 1, colour = segment_label)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = "grey60") +
  geom_point(size = 3) +
  geom_text_repel(aes(label = act_family), size = 3.3, show.legend = FALSE, seed = 1) +
  scale_x_log10() + scale_y_log10() +
  scale_colour_manual(values = SEGMENT_COLORS) +
  annotate("text", x = 300, y = 1.6, label = "album-led\n(fandom)", size = 3.2, colour = "grey40") +
  annotate("text", x = 2.5, y = 200, label = "song-led\n(mainstream)", size = 3.2, colour = "grey40") +
  labs(x = "Weeks on Billboard 200 (albums) + 1, log scale",
       y = "Weeks on Hot 100 (songs) + 1, log scale", colour = NULL,
       title = "Two routes into the US market",
       subtitle = "Acts with 20+ total chart weeks; dashed line = equal album and song weeks")
ggsave(file.path(out_fig, "album_vs_song_weeks.png"), p, width = 8, height = 6, dpi = 150, bg = "white")
write_table(acts[, c("act_family", "segment", "album_chart_weeks", "song_chart_weeks",
                     "albums_charted", "songs_charted", "best_album_pos", "best_song_pos")], "act_balance")

writeLines(capture.output(sessionInfo()), "output/sessionInfo.txt")
cat("Done.\n")
print(models)
print(album_summary)
print(top5)
print(song_summary)
