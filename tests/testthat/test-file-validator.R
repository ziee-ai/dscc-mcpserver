test_that("validate_omics_matrix accepts a well-formed features x samples CSV", {
  res <- validate_omics_matrix(fixture_path("omics1.csv"))
  expect_true(res$valid)
  expect_equal(res$n_features, 50L)
  expect_equal(res$n_samples, 30L)
  expect_true("sample01" %in% res$sample_names)
})

test_that("validate_omics_matrix flags too-few samples", {
  p <- tempfile(fileext = ".csv")
  writeLines(c("\"\",\"s1\"", "\"g1\",1", "\"g2\",2"), p)
  withr::defer(unlink(p))
  res <- validate_omics_matrix(p)
  expect_false(res$valid)
  expect_match(paste(res$issues, collapse = " "), "at least 2 samples")
})

test_that("validate_omics_matrix flags duplicate feature IDs", {
  p <- tempfile(fileext = ".csv")
  writeLines(c("\"\",\"s1\",\"s2\"", "\"g1\",1,2", "\"g1\",3,4", "\"g2\",5,6"), p)
  withr::defer(unlink(p))
  res <- validate_omics_matrix(p)
  expect_false(res$valid)
  expect_match(paste(res$issues, collapse = " "), "Duplicate feature IDs")
})

test_that("validate_omics_matrix flags non-numeric cells", {
  p <- tempfile(fileext = ".csv")
  writeLines(c("\"\",\"s1\",\"s2\"", "\"g1\",1,abc", "\"g2\",3,4", "\"g3\",5,6"), p)
  withr::defer(unlink(p))
  res <- validate_omics_matrix(p)
  expect_false(res$valid)
  expect_match(paste(res$issues, collapse = " "), "non-numeric")
})

test_that("validate_survival_table accepts a well-formed table", {
  res <- validate_survival_table(fixture_path("survival.csv"))
  expect_true(res$valid)
  expect_equal(res$n_samples, 30L)
  expect_true(res$n_events >= 0L)
  expect_equal(res$time_col, "os")
  expect_equal(res$event_col, "isDead")
  expect_true(nzchar(res$preview))
})

test_that("validate_survival_table accepts OSstatus/OS aliases", {
  p <- tempfile(fileext = ".csv")
  writeLines(c("sample,OS,OSstatus", "a,5,1", "b,9,0", "c,2,1"), p)
  withr::defer(unlink(p))
  res <- validate_survival_table(p)
  expect_true(res$valid)
  expect_equal(res$time_col, "OS")
  expect_equal(res$event_col, "OSstatus")
})

test_that("validate_survival_table rejects missing time/event columns", {
  p <- tempfile(fileext = ".csv")
  writeLines(c("sample,foo", "a,1", "b,2"), p)
  withr::defer(unlink(p))
  res <- validate_survival_table(p)
  expect_false(res$valid)
  expect_match(paste(res$issues, collapse = " "), "survival time column")
})

test_that("validate_survival_table rejects bad event values and negative times", {
  p <- tempfile(fileext = ".csv")
  writeLines(c("sample,os,isDead", "a,5,2", "b,-1,1", "c,3,0"), p)
  withr::defer(unlink(p))
  res <- validate_survival_table(p)
  expect_false(res$valid)
  joined <- paste(res$issues, collapse = " ")
  expect_match(joined, "0 \\(censored\\) or 1")
  expect_match(joined, "negative values")
})
