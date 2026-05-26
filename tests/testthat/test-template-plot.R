test_that("plot_subtypes template draws a Kaplan-Meier PNG", {
  skip_if_no_survival()
  clusters <- write_clusters_csv(sprintf("sample%02d", 1:30),
                                 clusters = rep(1:3, each = 10L))
  png_path <- tempfile(fileext = ".png")
  withr::defer(unlink(c(clusters, png_path)))

  res <- run_template("plot_subtypes", list(
    clusters_path = clusters,
    survival_path = fixture_path("survival.csv"),
    omics_paths = list(),
    plot_type = "kaplan_meier",
    png_path = png_path), timeout = 120)
  expect_true(res$result$success, info = paste("stderr:", res$result$stderr))
  expect_true(is_valid_png(png_path))
})

test_that("plot_subtypes template draws a silhouette PNG", {
  skip_if_no_dscc()  # needs the cluster package
  clusters <- write_clusters_csv(sprintf("sample%02d", 1:30),
                                 clusters = rep(1:3, each = 10L))
  png_path <- tempfile(fileext = ".png")
  withr::defer(unlink(c(clusters, png_path)))

  res <- run_template("plot_subtypes", list(
    clusters_path = clusters,
    survival_path = NULL,
    omics_paths = as.list(c(fixture_path("omics1.csv"),
                            fixture_path("omics2.csv"))),
    plot_type = "silhouette",
    png_path = png_path), timeout = 120)
  expect_true(res$result$success, info = paste("stderr:", res$result$stderr))
  expect_true(is_valid_png(png_path))
})
