# Default (unauthenticated) path via run_http_entrypoint with DSCC_AUTH=off.

skip_if_no_auth_deps()

srv <- NULL
withr::defer(teardown_dscc(srv), testthat::teardown_env())

test_that("auth off: initialize + tools/list succeed without a token", {
  srv <<- spawn_dscc(mode = "off")
  r <- http_call(srv$mcp_url, "POST",
                 headers = auth_headers(srv, token = NULL),
                 body = list(jsonrpc = "2.0", id = 1L, method = "initialize",
                             params = list(protocolVersion = "2025-06-18",
                                           capabilities = list())))
  expect_equal(httr2::resp_status(r), 200L)
  sid <- httr2::resp_header(r, "Mcp-Session-Id")
  expect_true(nzchar(sid))

  r2 <- http_call(srv$mcp_url, "POST",
                  headers = c(auth_headers(srv, token = NULL),
                              `Mcp-Session-Id` = sid),
                  body = list(jsonrpc = "2.0", id = 2L,
                              method = "tools/list", params = list()))
  expect_equal(httr2::resp_status(r2), 200L)
  names <- vapply(jsbody(r2)$result$tools, function(t) t$name, character(1L))
  expect_setequal(names, c("validate_input_file", "run_dscc_subtyping",
                           "evaluate_subtyping", "plot_subtypes"))
})

test_that("auth off: the admin surface is not mounted", {
  if (is.null(srv)) testthat::skip("server not started")
  r <- http_call(paste0(srv$url, "/admin/healthz"), "GET",
                 headers = c(Origin = "http://127.0.0.1"))
  expect_false(httr2::resp_status(r) == 200L)
})
