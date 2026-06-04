test_that("HTTP server responds to initialize", {
  skip_if_no_http_deps()
  port <- pick_free_port()
  srv <- spawn_dscc_server(port)
  withr::defer(stop_dscc_server(srv))

  resp <- post(srv,
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"i","version":"0"},"capabilities":{}}}')
  expect_equal(httr2::resp_status(resp), 200L)
  body <- parse_body(resp)
  expect_equal(body$result$serverInfo$name, "dscc-mcpserver")
  expect_true("tools" %in% names(body$result$capabilities))
})

test_that("HTTP tools/list returns all 4 DSCC tools", {
  skip_if_no_http_deps()
  port <- pick_free_port()
  srv <- spawn_dscc_server(port)
  withr::defer(stop_dscc_server(srv))

  post(srv,
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"i","version":"0"},"capabilities":{}}}')
  resp <- post(srv, '{"jsonrpc":"2.0","id":2,"method":"tools/list"}')
  expect_equal(httr2::resp_status(resp), 200L)
  body <- parse_body(resp)
  names_seen <- vapply(body$result$tools, function(t) t$name, character(1L))
  expect_setequal(names_seen, c(
    "validate_input_file", "run_dscc_subtyping",
    "evaluate_subtyping", "plot_subtypes"))
})

test_that("HTTP tools/call invokes validate_input_file end-to-end", {
  skip_if_no_http_deps()
  port <- pick_free_port()
  srv <- spawn_dscc_server(port)
  withr::defer(stop_dscc_server(srv))

  omics <- fixture_path("omics1.csv")
  post(srv,
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"i","version":"0"},"capabilities":{}}}')
  body <- sprintf(
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"validate_input_file","arguments":{"file_uri":"file://%s","file_type":"omics_matrix"}}}',
    normalizePath(omics, winslash = "/"))
  resp <- post(srv, body, timeout = 20)
  expect_equal(httr2::resp_status(resp), 200L)
  body <- parse_body(resp)
  expect_false(isTRUE(body$result$isError))
  txt <- body$result$content[[1L]]$text
  expect_match(txt, '"valid":true')
  expect_match(txt, '"n_features":50')
})

test_that("HTTP tools/call surfaces tool errors via isError=TRUE", {
  skip_if_no_http_deps()
  port <- pick_free_port()
  srv <- spawn_dscc_server(port)
  withr::defer(stop_dscc_server(srv))

  post(srv,
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"i","version":"0"},"capabilities":{}}}')
  resp <- post(srv,
    '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"validate_input_file","arguments":{"file_uri":"","file_type":"omics_matrix"}}}',
    timeout = 15)
  expect_equal(httr2::resp_status(resp), 200L)
  body <- parse_body(resp)
  expect_true(isTRUE(body$result$isError))
  expect_match(body$result$content[[1L]]$text, "file_uri is required")
})

test_that("HTTP request for unknown tool yields a JSON-RPC error", {
  skip_if_no_http_deps()
  port <- pick_free_port()
  srv <- spawn_dscc_server(port)
  withr::defer(stop_dscc_server(srv))

  post(srv,
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"i","version":"0"},"capabilities":{}}}')
  resp <- post(srv,
    '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"does_not_exist","arguments":{}}}')
  expect_equal(httr2::resp_status(resp), 200L)
  body <- parse_body(resp)
  expect_false(is.null(body$error))
  expect_match(body$error$message, "unknown tool")
})
