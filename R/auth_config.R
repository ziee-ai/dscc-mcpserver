# Auth bootstrap glue between dscc-mcpserver and mcpserver --------------
#
# This module decides, from environment variables only, whether and how
# to enable JWT auth + the admin REST API + the bundled admin SPA on
# top of the existing /mcp transport. The default is OFF so deployments
# stay unauthenticated unless `DSCC_AUTH=on` is set.
#
# The returned value is spliced into `mcpserver::serve_http(...)` by
# `run_http_entrypoint()` in R/static_server.R. When this returns NULL
# the caller forwards nothing, so serve_http() runs unauthenticated.

#' Build the auth-related kwargs for `mcpserver::serve_http()`
#'
#' Reads env vars and returns either `NULL` (auth disabled — the default)
#' or a list containing `oauth_as` and `admin` ready to be spliced into
#' the `serve_http()` call.
#'
#' Env vars consulted:
#'
#' * `DSCC_AUTH` — `"on"` to enable; anything else (default) leaves the
#'   server unauthenticated.
#' * `MCPSERVER_ADMIN_TOKEN` — bootstrap admin token. When unset and auth
#'   is on, an opaque 32-byte token is auto-generated and logged once.
#' * `DSCC_AUTH_DB` — SQLite path for the users + tokens store. Defaults
#'   to `<results_dir>/auth.db`.
#' * `DSCC_AUTH_ISSUER` — JWT `iss` claim and AS issuer URL. Defaults to
#'   `http://127.0.0.1:<port>`.
#' * `DSCC_AUTH_AUDIENCE` — JWT `aud` claim. Defaults to `dscc`.
#' * `DSCC_AUTH_UI` — `"on"` (default when auth is on) to mount the
#'   bundled `/admin/ui/*` SPA.
#'
#' @param port The port `serve_http()` will bind to (used to build the
#'   default issuer URL).
#' @return `NULL` (auth disabled) or `list(oauth_as = ..., admin = ...)`.
#' @keywords internal
dscc_auth_config <- function(port) {
  if (!identical(tolower(Sys.getenv("DSCC_AUTH", unset = "off")), "on")) {
    return(NULL)
  }

  # SQLite driver is only required when auth is on.
  for (pkg in c("DBI", "RSQLite")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf(
        "DSCC_AUTH=on requires the '%s' R package. ",
        pkg),
        "Install it (and any of: DBI, RSQLite) and restart, e.g. ",
        "`install.packages(c('DBI','RSQLite'))`.",
        call. = FALSE)
    }
  }

  # Bootstrap token: read from env, or auto-generate and log once.
  bootstrap_token <- Sys.getenv("MCPSERVER_ADMIN_TOKEN", unset = "")
  generated <- FALSE
  if (!nzchar(bootstrap_token)) {
    bootstrap_token <- paste(openssl::rand_bytes(32L), collapse = "")
    generated <- TRUE
  }

  auth_db <- Sys.getenv("DSCC_AUTH_DB", unset = "")
  if (!nzchar(auth_db)) {
    auth_db <- file.path(results_dir(), "auth.db")
  }
  dir.create(dirname(auth_db), recursive = TRUE, showWarnings = FALSE)

  issuer <- Sys.getenv(
    "DSCC_AUTH_ISSUER",
    unset = sprintf("http://127.0.0.1:%d", as.integer(port)))
  audience <- Sys.getenv("DSCC_AUTH_AUDIENCE", unset = "dscc")
  ui <- !identical(tolower(Sys.getenv("DSCC_AUTH_UI", unset = "on")),
                   "off")

  store <- mcpserver::new_mcp_store(driver = "sqlite", path = auth_db)
  oauth_as <- mcpserver::oauth_server_config(
    issuer   = issuer,
    audience = audience,
    store    = store
  )

  # One-time startup logging. Routed via message() so it lands on stderr
  # and inherits any DSCC_LOG sink configured by inst/run-http.R.
  if (isTRUE(generated)) {
    message("[Auth] MCPSERVER_ADMIN_TOKEN was not set; ",
            "generated an ephemeral one (will NOT survive restart): ",
            bootstrap_token)
    message("[Auth] Set MCPSERVER_ADMIN_TOKEN in your environment for ",
            "any persistent deployment.")
  }
  if (grepl("^/tmp(/|$)", auth_db)) {
    message("[Auth] WARNING: DSCC_AUTH_DB resolved to ", auth_db,
            " (under /tmp). Users and tokens will be lost on restart.")
  }
  message("[Auth] enabled; issuer=", issuer,
          " audience=", audience,
          " db=", auth_db,
          if (isTRUE(ui)) "; admin UI at /admin/ui" else "")

  list(
    oauth_as = oauth_as,
    admin = list(
      bootstrap_token = bootstrap_token,
      ui              = isTRUE(ui),
      # Cap minted token lifetimes at one year to keep the SQLite token
      # store from growing without bound on long-lived deployments.
      max_ttl         = 60L * 60L * 24L * 365L
    )
  )
}
