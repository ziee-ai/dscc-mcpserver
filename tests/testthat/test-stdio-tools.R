# All four DSCC tools exercised end-to-end over the stdio transport, in file
# results mode (file:// links resolved on disk). The three heavy tools are
# Tier-3 gated exactly like the rest of the suite (DSCC_RUN_TEMPLATE_TESTS +
# scientific packages); validate_input_file is covered in test-stdio-protocol.R.

# Sample names shared by the omics + survival fixtures, used to build synthetic
# clusters for the evaluate/plot tools.
fixture_samples <- function() {
  sv <- utils::read.csv(fixture_path("survival.csv"), stringsAsFactors = FALSE)
  if (!is.null(sv$sample)) sv$sample else sv[[1L]]
}

test_that("stdio run_dscc_subtyping produces clusters end-to-end", {
  skip_if_no_stdio_deps()
  skip_if_no_dscc()
  rdir <- withr::local_tempdir()
  srv <- spawn_dscc_stdio(results = "file", results_dir = rdir)
  withr::defer(stop_dscc_stdio(srv))

  stdio_initialize(srv)
  resp <- stdio_call_tool(srv, 2L, "run_dscc_subtyping",
    list(
      omics_uris = list(file_uri(fixture_path("omics1.csv")),
                        file_uri(fixture_path("omics2.csv"))),
      survival_uri = file_uri(fixture_path("survival.csv")),
      max_clusters = 6L),
    timeout_ms = 300000)

  expect_false(isTRUE(resp$result$isError), info = result_text(resp))
  txt <- result_text(resp)
  expect_match(txt, '"result_type":"dscc_subtyping"')
  meta <- jsonlite::fromJSON(txt)
  expect_equal(as.integer(meta$n_samples), 30L)
  expect_gte(meta$n_clusters, 2L)

  p <- link_path(resp)
  expect_false(is.na(p))
  expect_match(p, "clusters\\.csv$")
  expect_true(file.exists(p))
})

test_that("stdio evaluate_subtyping returns a Cox evaluation end-to-end", {
  skip_if_no_stdio_deps()
  skip_if_no_survival()
  rdir <- withr::local_tempdir()
  srv <- spawn_dscc_stdio(results = "file", results_dir = rdir)
  withr::defer(stop_dscc_stdio(srv))

  samples <- fixture_samples()
  clusters_csv <- write_clusters_csv(samples,
                                     clusters = rep(1:2, length.out = length(samples)))
  withr::defer(unlink(clusters_csv))

  stdio_initialize(srv)
  resp <- stdio_call_tool(srv, 2L, "evaluate_subtyping",
    list(
      clusters_uri = file_uri(clusters_csv),
      survival_uri = file_uri(fixture_path("survival.csv")),
      empirical = FALSE),
    timeout_ms = 120000)

  expect_false(isTRUE(resp$result$isError), info = result_text(resp))
  expect_match(result_text(resp), '"result_type":"dscc_evaluation"')

  p <- link_path(resp)
  expect_false(is.na(p))
  expect_match(p, "evaluation\\.json$")
  expect_true(file.exists(p))
})

test_that("stdio plot_subtypes produces a Kaplan-Meier PNG end-to-end", {
  skip_if_no_stdio_deps()
  skip_if_no_dscc()
  skip_if_not_installed("survival")
  rdir <- withr::local_tempdir()
  srv <- spawn_dscc_stdio(results = "file", results_dir = rdir)
  withr::defer(stop_dscc_stdio(srv))

  samples <- fixture_samples()
  clusters_csv <- write_clusters_csv(samples,
                                     clusters = rep(1:2, length.out = length(samples)))
  withr::defer(unlink(clusters_csv))

  stdio_initialize(srv)
  resp <- stdio_call_tool(srv, 2L, "plot_subtypes",
    list(
      clusters_uri = file_uri(clusters_csv),
      plot_type = "kaplan_meier",
      survival_uri = file_uri(fixture_path("survival.csv"))),
    timeout_ms = 120000)

  expect_false(isTRUE(resp$result$isError), info = result_text(resp))
  expect_match(result_text(resp), '"result_type":"dscc_plot"')

  p <- link_path(resp)
  expect_false(is.na(p))
  expect_match(p, "plot\\.png$")
  expect_true(file.exists(p))
  expect_true(is_valid_png(p))
})
