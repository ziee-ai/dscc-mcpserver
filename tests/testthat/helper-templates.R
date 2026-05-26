# Helpers for Tier-3 template smoke tests.
# These exercise the actual scientific R code inside each template by
# spawning a real Rscript subprocess. They need the DSCC scientific
# packages installed and DSCC_RUN_TEMPLATE_TESTS set.

skip_if_no_dscc <- function() {
  testthat::skip_if(
    !nzchar(Sys.getenv("DSCC_RUN_TEMPLATE_TESTS")),
    "DSCC_RUN_TEMPLATE_TESTS not set"
  )
  for (p in c("magrittr", "matrixStats", "SNFtool", "igraph", "cluster")) {
    testthat::skip_if_not_installed(p)
  }
}

skip_if_no_survival <- function() {
  testthat::skip_if(
    !nzchar(Sys.getenv("DSCC_RUN_TEMPLATE_TESTS")),
    "DSCC_RUN_TEMPLATE_TESTS not set"
  )
  testthat::skip_if_not_installed("survival")
}

# Run a template via the real make_job_script + Rscript subprocess path.
run_template <- function(template, params, timeout = 300) {
  run <- make_run_dir()
  job <- make_job_script(run$dir, "smoke", template, params)
  start <- Sys.time()
  res <- run_job_sync(job$script_path, "smoke")
  elapsed <- as.numeric(difftime(Sys.time(), start, units = "secs"))
  list(run_id = run$run_id,
       dir = run$dir,
       script = job$script_path,
       result = res,
       elapsed = elapsed)
}

# Absolute paths to the vendored sources, injected into subtyping params.
dscc_vendored <- function() {
  list(nemo_src = dscc_source_path("nemo_helpers.R"),
       dscc_src = dscc_source_path("DSCC_helper.R"))
}

# Check the first 8 bytes of a file against the PNG magic number.
is_valid_png <- function(path) {
  if (!file.exists(path)) return(FALSE)
  if (file.info(path)$size < 8L) return(FALSE)
  hdr <- readBin(path, what = "raw", n = 8L)
  identical(hdr, as.raw(c(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)))
}
