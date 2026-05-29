# Protocol-level stdio integration + the light validate_input_file tool.
# Always runs (no DSCC scientific deps needed). Mirrors test-http-integration.R
# plus stdio-only cases (parse error, batch).

test_that("stdio initialize returns serverInfo and capabilities", {
  skip_if_no_stdio_deps()
  srv <- spawn_dscc_stdio()
  withr::defer(stop_dscc_stdio(srv))

  init <- stdio_initialize(srv)
  expect_equal(init$result$serverInfo$name, "dscc-mcpserver")
  expect_true("tools" %in% names(init$result$capabilities))
})

test_that("stdio tools/list returns all 4 DSCC tools", {
  skip_if_no_stdio_deps()
  srv <- spawn_dscc_stdio()
  withr::defer(stop_dscc_stdio(srv))

  stdio_initialize(srv)
  send_msg(srv, list(jsonrpc = "2.0", id = 2L, method = "tools/list"))
  resp <- read_msg(srv)
  names_seen <- vapply(resp$result$tools, function(t) t$name, character(1L))
  expect_setequal(names_seen, c(
    "validate_input_file", "run_dscc_subtyping",
    "evaluate_subtyping", "plot_subtypes"))
})

test_that("stdio validate_input_file validates an omics matrix end-to-end", {
  skip_if_no_stdio_deps()
  srv <- spawn_dscc_stdio()
  withr::defer(stop_dscc_stdio(srv))

  stdio_initialize(srv)
  resp <- stdio_call_tool(srv, 3L, "validate_input_file",
    list(file_uri = file_uri(fixture_path("omics1.csv")),
         file_type = "omics_matrix"),
    timeout_ms = 30000)
  expect_false(isTRUE(resp$result$isError), info = result_text(resp))
  txt <- result_text(resp)
  expect_match(txt, '"valid":true')
  expect_match(txt, '"n_features":50')
})

test_that("stdio validate_input_file validates a survival table end-to-end", {
  skip_if_no_stdio_deps()
  srv <- spawn_dscc_stdio()
  withr::defer(stop_dscc_stdio(srv))

  stdio_initialize(srv)
  resp <- stdio_call_tool(srv, 4L, "validate_input_file",
    list(file_uri = file_uri(fixture_path("survival.csv")),
         file_type = "survival"),
    timeout_ms = 30000)
  expect_false(isTRUE(resp$result$isError), info = result_text(resp))
  txt <- result_text(resp)
  expect_match(txt, '"valid":true')
  expect_match(txt, '"file_type":"survival"')
})

test_that("stdio validate_input_file surfaces a missing file_uri as isError", {
  skip_if_no_stdio_deps()
  srv <- spawn_dscc_stdio()
  withr::defer(stop_dscc_stdio(srv))

  stdio_initialize(srv)
  resp <- stdio_call_tool(srv, 5L, "validate_input_file",
    list(file_uri = "", file_type = "omics_matrix"))
  expect_true(isTRUE(resp$result$isError))
  expect_match(result_text(resp), "file_uri is required")
})

test_that("stdio request for an unknown tool yields a JSON-RPC error", {
  skip_if_no_stdio_deps()
  srv <- spawn_dscc_stdio()
  withr::defer(stop_dscc_stdio(srv))

  stdio_initialize(srv)
  resp <- stdio_call_tool(srv, 6L, "does_not_exist", list())
  expect_false(is.null(resp$error))
  expect_match(resp$error$message, "unknown tool")
})

test_that("stdio rejects malformed JSON with -32700 parse_error", {
  skip_if_no_stdio_deps()
  srv <- spawn_dscc_stdio()
  withr::defer(stop_dscc_stdio(srv))

  stdio_initialize(srv)
  send_raw(srv, "{this is not valid json")
  resp <- read_msg(srv)
  expect_equal(resp$error$code, -32700L)
})

test_that("stdio handles a JSON-RPC batch (array of requests)", {
  skip_if_no_stdio_deps()
  srv <- spawn_dscc_stdio()
  withr::defer(stop_dscc_stdio(srv))

  stdio_initialize(srv)
  send_raw(srv, paste0(
    '[{"jsonrpc":"2.0","id":10,"method":"ping"},',
    '{"jsonrpc":"2.0","id":11,"method":"tools/list"}]'))
  r1 <- read_msg(srv)
  r2 <- read_msg(srv)
  expect_setequal(c(r1$id, r2$id), c(10, 11))
})

test_that("stdio responds to ping", {
  skip_if_no_stdio_deps()
  srv <- spawn_dscc_stdio()
  withr::defer(stop_dscc_stdio(srv))

  stdio_initialize(srv)
  send_msg(srv, list(jsonrpc = "2.0", id = 20L, method = "ping"))
  resp <- read_msg(srv)
  expect_equal(resp$id, 20)
  expect_equal(length(resp$result), 0L)
})
