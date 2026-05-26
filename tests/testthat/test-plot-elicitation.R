test_that("elicit_plot_args fills plot_type via request_elicitation", {
  ctx <- build_mock_ctx(list(
    list(action = "accept", content = list(plot_type = "silhouette"))
  ))
  args <- elicit_plot_args(list(clusters_uri = "http://x/c.csv"), ctx)
  expect_false(is_tool_error(args))
  expect_equal(args$plot_type, "silhouette")
  expect_length(ctx$.elicit_calls, 1L)
  enum <- ctx$.elicit_calls[[1L]]$schema$properties$plot_type$enum
  expect_setequal(as.character(enum), c("kaplan_meier", "silhouette"))
})

test_that("elicit_plot_args makes no call when plot_type is provided", {
  ctx <- build_mock_ctx(list())
  args <- elicit_plot_args(
    list(clusters_uri = "http://x/c.csv", plot_type = "kaplan_meier"), ctx)
  expect_false(is_tool_error(args))
  expect_equal(args$plot_type, "kaplan_meier")
  expect_length(ctx$.elicit_calls, 0L)
})

test_that("elicit_plot_args returns a tool error when the client declines", {
  ctx <- build_mock_ctx(list(list(action = "decline", content = list())))
  res <- elicit_plot_args(list(clusters_uri = "http://x/c.csv"), ctx)
  expect_true(is_tool_error(res))
  expect_match(error_text(res), "declined")
})

test_that("elicit_plot_args defaults to kaplan_meier without elicitation cap", {
  ctx <- build_mock_ctx(list())
  ctx$client_capabilities <- list()
  args <- elicit_plot_args(list(clusters_uri = "http://x/c.csv"), ctx)
  expect_false(is_tool_error(args))
  expect_equal(args$plot_type, "kaplan_meier")
  expect_length(ctx$.elicit_calls, 0L)
})
