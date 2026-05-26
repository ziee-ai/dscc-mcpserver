test_that("elicit_evaluate_args elicits empirical, then n_permutations when true", {
  ctx <- build_mock_ctx(list(
    list(action = "accept", content = list(empirical = TRUE)),
    list(action = "accept", content = list(n_permutations = 500L))
  ))
  args <- elicit_evaluate_args(
    list(clusters_uri = "http://x/c.csv", survival_uri = "http://x/s.csv"), ctx)
  expect_false(is_tool_error(args))
  expect_true(args$empirical)
  expect_equal(args$n_permutations, 500L)
  expect_length(ctx$.elicit_calls, 2L)
})

test_that("elicit_evaluate_args elicits only empirical when false", {
  ctx <- build_mock_ctx(list(
    list(action = "accept", content = list(empirical = FALSE))
  ))
  args <- elicit_evaluate_args(
    list(clusters_uri = "http://x/c.csv", survival_uri = "http://x/s.csv"), ctx)
  expect_false(is_tool_error(args))
  expect_false(args$empirical)
  expect_length(ctx$.elicit_calls, 1L)
})

test_that("elicit_evaluate_args makes no call when empirical is provided", {
  ctx <- build_mock_ctx(list())
  args <- elicit_evaluate_args(
    list(clusters_uri = "http://x/c.csv", survival_uri = "http://x/s.csv",
         empirical = FALSE), ctx)
  expect_false(is_tool_error(args))
  expect_false(args$empirical)
  expect_length(ctx$.elicit_calls, 0L)
})

test_that("elicit_evaluate_args returns a tool error when the client declines", {
  ctx <- build_mock_ctx(list(list(action = "decline", content = list())))
  res <- elicit_evaluate_args(
    list(clusters_uri = "http://x/c.csv", survival_uri = "http://x/s.csv"), ctx)
  expect_true(is_tool_error(res))
  expect_match(error_text(res), "declined")
})

test_that("elicit_evaluate_args defaults to non-empirical without elicitation cap", {
  ctx <- build_mock_ctx(list())
  ctx$client_capabilities <- list()
  args <- elicit_evaluate_args(
    list(clusters_uri = "http://x/c.csv", survival_uri = "http://x/s.csv"), ctx)
  expect_false(is_tool_error(args))
  expect_false(args$empirical)
  expect_length(ctx$.elicit_calls, 0L)
})
