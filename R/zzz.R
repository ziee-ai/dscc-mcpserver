`%||%` <- function(a, b) if (!is.null(a)) a else b

.pkg_env <- new.env(parent = emptyenv())

.onLoad <- function(libname, pkgname) {
  .pkg_env$results_dir <- Sys.getenv("DSCC_RESULTS_DIR",
                                     unset = file.path(tempdir(), "dscc-results"))
  .pkg_env$base_url <- Sys.getenv("BASE_URL",
                                   unset = "http://localhost:9007")
  .pkg_env$rscript <- file.path(R.home("bin"), "Rscript")
  dir.create(.pkg_env$results_dir, recursive = TRUE, showWarnings = FALSE)
  invisible()
}

results_dir <- function() .pkg_env$results_dir
base_url <- function() .pkg_env$base_url
rscript_path <- function() .pkg_env$rscript

# Build the URI a tool emits for a result file. Over the static HTTP server
# (the default and HTTP-transport behaviour) this is an http(s) URL the server
# resolves by stripping the /results/ prefix. Over stdio with file results mode
# (DSCC_RESULTS_MODE=file) it is a file:// path to the result on disk, so a
# local client can read it without a running HTTP server.
result_uri <- function(run_id, filename,
                       mode = Sys.getenv("DSCC_RESULTS_MODE", unset = "http")) {
  if (identical(mode, "file")) {
    # Normalize the (existing) results dir once — forward slashes on Windows
    # and a consistent real path on macOS (/var -> /private/var) — then append
    # run_id/filename so a not-yet-created file still yields a valid URI.
    base <- normalizePath(results_dir(), mustWork = FALSE, winslash = "/")
    paste0("file://", base, "/", run_id, "/", filename)
  } else {
    paste0(base_url(), "/results/", run_id, "/", filename)
  }
}

template_path <- function(name) {
  p <- system.file("templates", paste0(name, ".R"), package = "dscc.mcpserver")
  if (!nzchar(p) || !file.exists(p)) {
    p <- file.path("inst", "templates", paste0(name, ".R"))
  }
  p
}

# Absolute path to a vendored DSCC source file (inst/dscc/<name>), used by
# the subprocess templates so they can source() the scientific code.
dscc_source_path <- function(name) {
  p <- system.file("dscc", name, package = "dscc.mcpserver")
  if (!nzchar(p) || !file.exists(p)) {
    p <- file.path("inst", "dscc", name)
  }
  p
}
