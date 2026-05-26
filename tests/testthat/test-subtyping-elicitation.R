test_that("elicit_subtyping_args fills max_clusters via request_elicitation", {
  ctx <- build_mock_ctx(list(
    list(action = "accept", content = list(max_clusters = 4L))
  ))
  args <- elicit_subtyping_args(
    list(omics_uris = list("http://x/a.csv")), ctx)
  expect_false(is_tool_error(args))
  expect_equal(args$max_clusters, 4L)
  expect_length(ctx$.elicit_calls, 1L)
  # The elicitation schema offers an integer max_clusters field.
  expect_equal(ctx$.elicit_calls[[1L]]$schema$properties$max_clusters$type,
               "integer")
})

test_that("elicit_subtyping_args makes no call when max_clusters is provided", {
  ctx <- build_mock_ctx(list())  # empty queue: any call would error
  args <- elicit_subtyping_args(
    list(omics_uris = list("http://x/a.csv"), max_clusters = 8L), ctx)
  expect_false(is_tool_error(args))
  expect_equal(args$max_clusters, 8L)
  expect_length(ctx$.elicit_calls, 0L)
})

test_that("elicit_subtyping_args returns a tool error when the client declines", {
  ctx <- build_mock_ctx(list(list(action = "decline", content = list())))
  res <- elicit_subtyping_args(list(omics_uris = list("http://x/a.csv")), ctx)
  expect_true(is_tool_error(res))
  expect_match(error_text(res), "declined")
})

test_that("elicit_subtyping_args falls back to the default without elicitation cap", {
  ctx <- build_mock_ctx(list())
  ctx$client_capabilities <- list()  # no elicitation capability
  args <- elicit_subtyping_args(list(omics_uris = list("http://x/a.csv")), ctx)
  expect_false(is_tool_error(args))
  expect_equal(args$max_clusters, .DSCC_DEFAULT_MAX_CLUSTERS)
  expect_length(ctx$.elicit_calls, 0L)
})

test_that("elicit_subtyping_args elicits omics_names for 2+ layers", {
  ctx <- build_mock_ctx(list(
    list(action = "accept", content = list(max_clusters = 5L)),
    list(action = "accept", content = list(omics_names = list("rna", "meth")))
  ))
  args <- elicit_subtyping_args(
    list(omics_uris = list("http://x/a.csv", "http://x/b.csv")), ctx)
  expect_false(is_tool_error(args))
  expect_equal(args$max_clusters, 5L)
  expect_equal(unlist(args$omics_names), c("rna", "meth"))
  expect_length(ctx$.elicit_calls, 2L)
  # Second call carries the array label schema.
  expect_equal(ctx$.elicit_calls[[2L]]$schema$properties$omics_names$type, "array")
})

test_that("elicit_subtyping_args does not elicit labels for a single layer", {
  ctx <- build_mock_ctx(list())  # empty queue: any call would error
  args <- elicit_subtyping_args(
    list(omics_uris = list("http://x/a.csv"), max_clusters = 4L), ctx)
  expect_false(is_tool_error(args))
  expect_equal(unlist(args$omics_names), "omics_1")
  expect_length(ctx$.elicit_calls, 0L)
})

test_that("elicit_subtyping_args defaults labels when the client declines them", {
  ctx <- build_mock_ctx(list(
    list(action = "decline", content = list())
  ))
  args <- elicit_subtyping_args(
    list(omics_uris = list("http://x/a.csv", "http://x/b.csv"),
         max_clusters = 6L), ctx)
  expect_false(is_tool_error(args))
  expect_equal(unlist(args$omics_names), c("omics_1", "omics_2"))
  expect_length(ctx$.elicit_calls, 1L)
})

test_that("elicit_subtyping_args makes no label call when names are provided", {
  ctx <- build_mock_ctx(list())  # empty queue: any call would error
  args <- elicit_subtyping_args(
    list(omics_uris = list("http://x/a.csv", "http://x/b.csv"),
         omics_names = list("rna", "meth"), max_clusters = 6L), ctx)
  expect_false(is_tool_error(args))
  expect_equal(unlist(args$omics_names), c("rna", "meth"))
  expect_length(ctx$.elicit_calls, 0L)
})
