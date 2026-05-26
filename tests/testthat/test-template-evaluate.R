test_that("evaluate_subtyping template computes a Cox p-value", {
  skip_if_no_survival()
  clusters <- write_clusters_csv(sprintf("sample%02d", 1:30),
                                 clusters = rep(1:3, each = 10L))
  eval_json <- tempfile(fileext = ".json")
  withr::defer(unlink(c(clusters, eval_json)))

  res <- run_template("evaluate_subtyping", list(
    clusters_path = clusters,
    survival_path = fixture_path("survival.csv"),
    empirical = FALSE,
    n_permutations = 200L,
    eval_json = eval_json), timeout = 120)
  expect_true(res$result$success, info = paste("stderr:", res$result$stderr))
  out <- jsonlite::fromJSON(eval_json)
  expect_true(is.numeric(out$cox_pvalue))
  expect_equal(out$n_clusters, 3L)
  expect_equal(out$n_samples, 30L)
})

test_that("evaluate_subtyping template returns an empirical p-value when asked", {
  skip_if_no_survival()
  clusters <- write_clusters_csv(sprintf("sample%02d", 1:30),
                                 clusters = rep(1:3, each = 10L))
  eval_json <- tempfile(fileext = ".json")
  withr::defer(unlink(c(clusters, eval_json)))

  res <- run_template("evaluate_subtyping", list(
    clusters_path = clusters,
    survival_path = fixture_path("survival.csv"),
    empirical = TRUE,
    n_permutations = 200L,
    eval_json = eval_json), timeout = 120)
  expect_true(res$result$success, info = paste("stderr:", res$result$stderr))
  out <- jsonlite::fromJSON(eval_json)
  expect_true("empirical_pvalue" %in% names(out))
  expect_equal(out$n_permutations, 200L)
  expect_true(out$empirical_pvalue >= 0 && out$empirical_pvalue <= 1)
})
