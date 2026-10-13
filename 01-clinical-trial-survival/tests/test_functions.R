# Run with: Rscript -e 'testthat::test_dir("tests")'  (from the project folder)
library(testthat)
source(file.path("..", "R", "functions.R"), chdir = TRUE)

d <- prep_pbc()

test_that("ITT population and endpoints are derived correctly", {
  expect_equal(nrow(d), 312)
  expect_equal(sum(d$death), 125)
  expect_equal(as.vector(table(d$arm)), c(154, 158))
  # transplant counts toward the composite but not the primary endpoint
  expect_true(all(d$death_tx >= d$death))
  expect_equal(sum(d$death_tx - d$death), sum(d$event_cr == "transplant"))
  expect_equal(levels(d$arm)[1], "Placebo")
})

test_that("log-rank test matches survdiff", {
  lr <- logrank_test(d)
  ref <- survdiff(Surv(years, death) ~ arm, data = d)
  expect_equal(lr$chisq, unname(ref$chisq))
  expect_gt(lr$p_value, 0.05)
})

test_that("RMST difference is consistent with the per-arm estimates", {
  r <- rmst_difference(d, tau = 10)
  expect_equal(r$difference, r$rmst_dpca - r$rmst_placebo)
  expect_lt(r$lower, r$difference)
  expect_gt(r$upper, r$difference)
  expect_true(r$rmst_placebo > 0 && r$rmst_placebo <= 10)
})

test_that("tidy_hr exponentiates coefficients", {
  fit <- fit_cox(d, Surv(years, death) ~ arm)
  h <- tidy_hr(fit)
  expect_equal(h$hr, unname(exp(coef(fit))))
  expect_true(h$lower < h$hr && h$hr < h$upper)
})

test_that("SMD helpers return 0 for identical groups", {
  g <- factor(rep(c("a", "b"), each = 4))
  expect_equal(smd_continuous(c(1, 2, 3, 4, 1, 2, 3, 4), g), 0)
  expect_equal(smd_categorical(factor(c("x", "y", "x", "y", "x", "y", "x", "y")), g), 0)
})

test_that("Table 1 has one column per arm plus SMD", {
  t1 <- table_one(d)
  expect_true(all(c("Placebo (n=154)", "D-penicillamine (n=158)", "SMD") %in% names(t1)))
})

test_that("Schoenfeld power formulas are inverses of each other", {
  ev <- logrank_events(0.7, power = 0.8)
  expect_gte(logrank_power(ev, 0.7), 0.8)
  expect_lt(logrank_power(ev - 1, 0.7), 0.8)
})

test_that("subgroup analysis returns two levels per subgroup", {
  sg <- subgroup_hr(d, list(Sex = function(d) d$sex))
  expect_equal(nrow(sg), 2)
  expect_equal(sum(sg$n), nrow(d))
  expect_false(is.na(sg$p_interaction[1]))
})
