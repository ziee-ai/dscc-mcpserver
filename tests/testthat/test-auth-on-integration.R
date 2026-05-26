# Enforced-auth suite via run_http_entrypoint with DSCC_AUTH=on.

skip_if_no_auth_deps()

srv <- NULL
withr::defer(teardown_dscc(srv), testthat::teardown_env())

start_once <- function() {
  if (!is.null(srv) && srv$process$is_alive()) return(invisible(srv))
  srv <<- spawn_dscc(mode = "on")
  invisible(srv)
}

init_session <- function(srv, token) {
  r <- http_call(srv$mcp_url, "POST",
                 headers = auth_headers(srv, token = token),
                 body = list(jsonrpc = "2.0", id = 1L, method = "initialize",
                             params = list(protocolVersion = "2025-06-18",
                                           capabilities = list())))
  expect_equal(httr2::resp_status(r), 200L)
  httr2::resp_header(r, "Mcp-Session-Id")
}

test_that("POST /mcp without bearer is 401 + WWW-Authenticate", {
  start_once()
  r <- http_call(srv$mcp_url, "POST",
                 headers = auth_headers(srv, token = NULL),
                 body = list(jsonrpc = "2.0", id = 1L,
                             method = "tools/list", params = list()))
  expect_equal(httr2::resp_status(r), 401L)
  www <- httr2::resp_header(r, "WWW-Authenticate") %||% ""
  expect_match(www, "Bearer", fixed = TRUE)
})

test_that("/admin/healthz with the bootstrap token is 200", {
  start_once()
  r <- http_call(paste0(srv$url, "/admin/healthz"), "GET",
                 headers = auth_headers(srv))
  expect_equal(httr2::resp_status(r), 200L)
})

test_that("mint a token, use it on /mcp, revoke it, then 401", {
  start_once()
  cu <- http_call(paste0(srv$url, "/admin/users"), "POST",
                  headers = auth_headers(srv),
                  body = list(username = paste0("bob-", as.integer(Sys.time()))))
  expect_equal(httr2::resp_status(cu), 201L)
  uid <- jsbody(cu)$id

  m <- jsbody(http_call(paste0(srv$url, "/admin/tokens/mint"), "POST",
                        headers = auth_headers(srv),
                        body = list(user_id = uid, name = "ci",
                                    scopes = list(), ttl = 600L)))
  expect_true(nzchar(m$jti))
  expect_match(m$token, "^eyJ")

  sid <- init_session(srv, token = m$token)
  ok <- http_call(srv$mcp_url, "POST",
                  headers = c(auth_headers(srv, token = m$token),
                              `Mcp-Session-Id` = sid),
                  body = list(jsonrpc = "2.0", id = 2L,
                              method = "tools/list", params = list()))
  expect_equal(httr2::resp_status(ok), 200L)
  names <- vapply(jsbody(ok)$result$tools, function(t) t$name, character(1L))
  expect_true("run_dscc_subtyping" %in% names)

  rev <- http_call(sprintf("%s/admin/tokens/%s/revoke", srv$url, m$jti),
                   "POST", headers = auth_headers(srv))
  expect_equal(httr2::resp_status(rev), 204L)

  dead <- http_call(srv$mcp_url, "POST",
                    headers = c(auth_headers(srv, token = m$token),
                                `Mcp-Session-Id` = sid),
                    body = list(jsonrpc = "2.0", id = 3L,
                                method = "tools/list", params = list()))
  expect_equal(httr2::resp_status(dead), 401L)
})

test_that("tools/call validate_input_file works with a minted JWT", {
  start_once()
  cu <- http_call(paste0(srv$url, "/admin/users"), "POST",
                  headers = auth_headers(srv),
                  body = list(username = paste0("dave-", as.integer(Sys.time()))))
  uid <- jsbody(cu)$id
  m <- jsbody(http_call(paste0(srv$url, "/admin/tokens/mint"), "POST",
                        headers = auth_headers(srv),
                        body = list(user_id = uid, name = "live",
                                    scopes = list(), ttl = 600L)))
  sid <- init_session(srv, token = m$token)
  csv_path <- file.path(srv$results_dir, "auth-on-omics.csv")
  writeLines(c("\"\",\"s1\",\"s2\"", "\"g1\",1,2", "\"g2\",3,4", "\"g3\",5,6"),
             csv_path)
  r <- http_call(srv$mcp_url, "POST",
                 headers = c(auth_headers(srv, token = m$token),
                             `Mcp-Session-Id` = sid),
                 body = list(jsonrpc = "2.0", id = 2L, method = "tools/call",
                             params = list(name = "validate_input_file",
                                           arguments = list(
                                             file_uri = paste0("file://", csv_path),
                                             file_type = "omics_matrix"))),
                 timeout = 30)
  expect_equal(httr2::resp_status(r), 200L)
  body <- jsbody(r)
  expect_false(isTRUE(body$result$isError))
  parsed <- jsonlite::fromJSON(body$result$content[[1L]]$text,
                               simplifyVector = FALSE)
  expect_equal(parsed$n_features, 3L)
})
