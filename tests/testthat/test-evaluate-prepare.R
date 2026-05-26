test_that("evaluate_prepare builds a runnable job from clusters + survival", {
  clusters <- write_clusters_csv(sprintf("sample%02d", 1:30))
  withr::defer(unlink(clusters))
  prep <- evaluate_prepare(list(
    clusters_uri = file_uri(clusters),
    survival_uri = file_uri(fixture_path("survival.csv")),
    empirical = FALSE, n_permutations = 1000L))
  expect_null(prep$error)
  expect_true(file.exists(prep$script_path))
  expect_match(prep$eval_url, "/results/.*/evaluation\\.json$")
})

test_that("evaluate_prepare errors without clusters_uri", {
  prep <- evaluate_prepare(list(clusters_uri = "",
                                survival_uri = file_uri(fixture_path("survival.csv"))))
  expect_true(is_tool_error(prep$error))
  expect_match(error_text(prep$error), "clusters_uri is required")
})

test_that("evaluate_prepare errors without survival_uri", {
  clusters <- write_clusters_csv(sprintf("sample%02d", 1:30))
  withr::defer(unlink(clusters))
  prep <- evaluate_prepare(list(clusters_uri = file_uri(clusters),
                                survival_uri = ""))
  expect_true(is_tool_error(prep$error))
  expect_match(error_text(prep$error), "survival_uri is required")
})

test_that("evaluate_prepare rejects a clusters file without a cluster column", {
  bad <- tempfile(fileext = ".csv")
  writeLines(c("sample,foo", "a,1", "b,2"), bad)
  withr::defer(unlink(bad))
  prep <- evaluate_prepare(list(clusters_uri = file_uri(bad),
                                survival_uri = file_uri(fixture_path("survival.csv"))))
  expect_true(is_tool_error(prep$error))
  expect_match(error_text(prep$error), "'sample' and 'cluster' columns")
})
