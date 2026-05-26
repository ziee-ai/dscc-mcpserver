test_that("plot_prepare builds a kaplan_meier job from clusters + survival", {
  clusters <- write_clusters_csv(sprintf("sample%02d", 1:30))
  withr::defer(unlink(clusters))
  prep <- plot_prepare(list(
    clusters_uri = file_uri(clusters),
    survival_uri = file_uri(fixture_path("survival.csv")),
    plot_type = "kaplan_meier"))
  expect_null(prep$error)
  expect_true(file.exists(prep$script_path))
  expect_equal(prep$plot_type, "kaplan_meier")
  expect_match(prep$png_url, "/results/.*/plot\\.png$")
})

test_that("plot_prepare builds a silhouette job from clusters + omics", {
  clusters <- write_clusters_csv(sprintf("sample%02d", 1:30))
  withr::defer(unlink(clusters))
  prep <- plot_prepare(list(
    clusters_uri = file_uri(clusters),
    omics_uris = list(file_uri(fixture_path("omics1.csv"))),
    plot_type = "silhouette"))
  expect_null(prep$error)
  expect_equal(prep$plot_type, "silhouette")
})

test_that("plot_prepare requires survival_uri for kaplan_meier", {
  clusters <- write_clusters_csv(sprintf("sample%02d", 1:30))
  withr::defer(unlink(clusters))
  prep <- plot_prepare(list(clusters_uri = file_uri(clusters),
                            plot_type = "kaplan_meier"))
  expect_true(is_tool_error(prep$error))
  expect_match(error_text(prep$error), "survival_uri is required")
})

test_that("plot_prepare requires omics_uris for silhouette", {
  clusters <- write_clusters_csv(sprintf("sample%02d", 1:30))
  withr::defer(unlink(clusters))
  prep <- plot_prepare(list(clusters_uri = file_uri(clusters),
                            plot_type = "silhouette"))
  expect_true(is_tool_error(prep$error))
  expect_match(error_text(prep$error), "omics_uris is required")
})

test_that("plot_prepare rejects an unknown plot_type", {
  clusters <- write_clusters_csv(sprintf("sample%02d", 1:30))
  withr::defer(unlink(clusters))
  prep <- plot_prepare(list(clusters_uri = file_uri(clusters),
                            plot_type = "scatter"))
  expect_true(is_tool_error(prep$error))
  expect_match(error_text(prep$error), "plot_type must be")
})
