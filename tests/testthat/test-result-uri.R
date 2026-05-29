test_that("result_uri builds file:// paths under the results dir in file mode", {
  uri <- result_uri("RID123", "clusters.csv", mode = "file")
  expect_true(startsWith(uri, "file://"))
  expect_true(endsWith(uri, "/RID123/clusters.csv"))
  path <- sub("^file://", "", uri)
  expect_true(startsWith(
    normalizePath(path, mustWork = FALSE),
    normalizePath(results_dir(), mustWork = FALSE)))
})

test_that("result_uri keeps the http static-server shape in http mode", {
  uri <- result_uri("RID123", "clusters.csv", mode = "http")
  expect_equal(uri, paste0(base_url(), "/results/RID123/clusters.csv"))
})

test_that("result_uri defaults to http mode when DSCC_RESULTS_MODE is unset", {
  withr::with_envvar(c(DSCC_RESULTS_MODE = NA), {
    uri <- result_uri("RID", "f.csv")
    expect_equal(uri, paste0(base_url(), "/results/RID/f.csv"))
  })
})

test_that("result_uri honours DSCC_RESULTS_MODE=file via the default arg", {
  withr::with_envvar(c(DSCC_RESULTS_MODE = "file"), {
    uri <- result_uri("RID", "f.csv")
    expect_true(startsWith(uri, "file://"))
  })
})
