test_that("subtyping_prepare builds a runnable job from valid omics layers", {
  prep <- subtyping_prepare(list(
    omics_uris = list(file_uri(fixture_path("omics1.csv")),
                      file_uri(fixture_path("omics2.csv"))),
    max_clusters = 6L))
  expect_null(prep$error)
  expect_true(file.exists(prep$script_path))
  expect_equal(prep$n_omics, 2L)
  expect_equal(prep$max_clusters, 6L)
  expect_false(prep$has_survival)
  expect_match(prep$clusters_url, "/results/.*/clusters\\.csv$")
  # The job params reference the vendored sources.
  params_file <- sub("\\.R$", "_params.json", prep$script_path)
  params <- jsonlite::fromJSON(params_file)
  expect_true(file.exists(params$dscc_src))
  expect_true(file.exists(params$nemo_src))
})

test_that("subtyping_prepare records survival when provided", {
  prep <- subtyping_prepare(list(
    omics_uris = list(file_uri(fixture_path("omics1.csv"))),
    survival_uri = file_uri(fixture_path("survival.csv")),
    max_clusters = 5L))
  expect_null(prep$error)
  expect_true(prep$has_survival)
})

test_that("subtyping_prepare errors when no omics layers are given", {
  prep <- subtyping_prepare(list(omics_uris = list(), max_clusters = 5L))
  expect_true(is_tool_error(prep$error))
  expect_match(error_text(prep$error), "omics_uris is required")
})

test_that("subtyping_prepare errors on an invalid omics layer", {
  bad <- tempfile(fileext = ".csv")
  writeLines(c("\"\",\"s1\"", "\"g1\",1", "\"g2\",2"), bad)
  withr::defer(unlink(bad))
  prep <- subtyping_prepare(list(omics_uris = list(file_uri(bad)),
                                 max_clusters = 5L))
  expect_true(is_tool_error(prep$error))
  expect_match(error_text(prep$error), "is invalid")
})
