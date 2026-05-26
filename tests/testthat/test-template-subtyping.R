test_that("dscc_subtyping template produces a clusters CSV on the fixtures", {
  skip_if_no_dscc()
  clusters_csv <- tempfile(fileext = ".csv")
  clusters_rds <- tempfile(fileext = ".rds")
  withr::defer(unlink(c(clusters_csv, clusters_rds)))

  params <- c(list(
    omics_paths = as.list(c(fixture_path("omics1.csv"),
                            fixture_path("omics2.csv"))),
    omics_names = list("rna", "prot"),
    max_clusters = 6L,
    survival_path = NULL,
    clusters_csv = clusters_csv,
    clusters_rds = clusters_rds,
    cox_json = tempfile(fileext = ".json")
  ), dscc_vendored())

  res <- run_template("dscc_subtyping", params, timeout = 300)
  expect_true(res$result$success,
              info = paste("stderr:", res$result$stderr))
  expect_true(file.exists(clusters_csv))
  cl <- utils::read.csv(clusters_csv, stringsAsFactors = FALSE)
  expect_true(all(c("sample", "cluster") %in% colnames(cl)))
  expect_equal(nrow(cl), 30L)
  expect_gte(length(unique(cl$cluster)), 2L)
})

test_that("dscc_subtyping template computes a Cox p-value when survival is given", {
  skip_if_no_dscc()
  skip_if_not_installed("survival")
  clusters_csv <- tempfile(fileext = ".csv")
  cox_json <- tempfile(fileext = ".json")
  withr::defer(unlink(c(clusters_csv, cox_json)))

  params <- c(list(
    omics_paths = as.list(c(fixture_path("omics1.csv"),
                            fixture_path("omics2.csv"))),
    omics_names = list("rna", "prot"),
    max_clusters = 6L,
    survival_path = fixture_path("survival.csv"),
    clusters_csv = clusters_csv,
    clusters_rds = tempfile(fileext = ".rds"),
    cox_json = cox_json
  ), dscc_vendored())

  res <- run_template("dscc_subtyping", params, timeout = 300)
  expect_true(res$result$success,
              info = paste("stderr:", res$result$stderr))
  expect_true(file.exists(cox_json))
  cox <- jsonlite::fromJSON(cox_json)
  expect_true("cox_pvalue" %in% names(cox))
})
