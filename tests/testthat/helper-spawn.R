# Full HTTP integration: spawn serve_http in a child Rscript process and
# drive it via httr2 (serve_http runs the dispatcher on the same thread,
# so an in-process httr2 call would deadlock it).

skip_if_no_http_deps <- function() {
  testthat::skip_if_not_installed("processx")
  testthat::skip_if_not_installed("httr2")
  testthat::skip_if_not_installed("nanonext")
  testthat::skip_on_cran()
}

spawn_dscc_server <- function(port, allow_local = TRUE, startup_wait = 4) {
  runner_script <- tempfile(fileext = ".R")
  writeLines(c(
    "suppressPackageStartupMessages(library(mcpserver))",
    "suppressPackageStartupMessages(library(dscc.mcpserver))",
    "srv <- build_dscc_server()",
    sprintf("serve_http(srv, host = '127.0.0.1', port = %dL,", port),
    "           path = '/mcp',",
    "           allowed_origins = c('http://127.0.0.1', 'http://localhost'),",
    "           require_origin = FALSE,",
    "           stateless = TRUE,",
    "           daemons = 2L)"
  ), runner_script)
  child_env <- Sys.getenv()
  child_env["R_LIBS"] <- paste(.libPaths(), collapse = .Platform$path.sep)
  child_env["DSCC_ALLOW_LOCAL_URIS"] <- if (isTRUE(allow_local)) "TRUE" else "FALSE"
  p <- processx::process$new("Rscript", c(runner_script),
                              stdout = "|", stderr = "|", env = child_env)
  Sys.sleep(startup_wait)
  if (!p$is_alive()) {
    err <- tryCatch(p$read_all_error(), error = function(e) "")
    out <- tryCatch(p$read_all_output(), error = function(e) "")
    stop(sprintf("server failed to start: stderr=%s\nstdout=%s", err, out))
  }
  list(process = p, port = port,
       url = sprintf("http://127.0.0.1:%d/mcp", port),
       runner_script = runner_script)
}

stop_dscc_server <- function(server) {
  tryCatch(server$process$kill(), error = function(e) NULL)
  tryCatch(unlink(server$runner_script), error = function(e) NULL)
}

post <- function(server, body, timeout = 10) {
  req <- httr2::request(server$url) |>
    httr2::req_method("POST") |>
    httr2::req_headers(
      Origin = "http://127.0.0.1",
      `Content-Type` = "application/json",
      Accept = "application/json, text/event-stream"
    ) |>
    httr2::req_body_raw(charToRaw(body)) |>
    httr2::req_error(is_error = function(r) FALSE) |>
    httr2::req_timeout(timeout)
  httr2::req_perform(req)
}

pick_free_port <- function() {
  for (attempt in seq_len(20L)) {
    port <- sample(20000:60000, 1L)
    can_bind <- tryCatch({
      s <- nanonext::socket("rep")
      on.exit(nanonext::reap(s), add = TRUE)
      nanonext::listen(s, sprintf("tcp://127.0.0.1:%d", port))
      TRUE
    }, error = function(e) FALSE)
    if (isTRUE(can_bind)) return(port)
  }
  stop("could not find a free port after 20 attempts")
}

parse_body <- function(resp) {
  text <- httr2::resp_body_string(resp)
  text <- gsub("\r\n", "\n", text)
  if (grepl("^event: |^data: ", text)) {
    m <- regmatches(text, regexpr("(?m)^data:\\s*(.+)$", text, perl = TRUE))
    if (length(m) > 0L) {
      json <- sub("^data:\\s*", "", m[[1L]])
      return(jsonlite::fromJSON(json, simplifyVector = FALSE))
    }
  }
  jsonlite::fromJSON(text, simplifyVector = FALSE)
}
