test_that("make_run_dir creates a unique directory under the results dir", {
  r1 <- make_run_dir()
  r2 <- make_run_dir()
  expect_true(dir.exists(r1$dir))
  expect_true(dir.exists(r2$dir))
  expect_false(identical(r1$run_id, r2$run_id))
})

test_that("make_job_script writes params + a script that sources the template", {
  run <- make_run_dir()
  job <- make_job_script(run$dir, "myjob", "dscc_subtyping",
                         list(max_clusters = 5L, omics_paths = list("a", "b")))
  expect_true(file.exists(job$script_path))
  expect_true(file.exists(job$params_path))
  script <- readLines(job$script_path)
  expect_match(paste(script, collapse = "\n"), "library\\(jsonlite\\)")
  expect_match(paste(script, collapse = "\n"), "dscc_subtyping\\.R")
  params <- jsonlite::fromJSON(job$params_path)
  expect_equal(params$max_clusters, 5L)
})

test_that("make_job_script errors on an unknown template", {
  run <- make_run_dir()
  expect_error(make_job_script(run$dir, "j", "no_such_template", list()),
               "not found")
})

test_that("run_job_sync runs a trivial script and reports success", {
  skip_on_cran()
  run <- make_run_dir()
  script <- file.path(run$dir, "trivial.R")
  writeLines("cat('hello from subprocess\\n')", script)
  res <- run_job_sync(script, "trivial")
  expect_true(res$success)
  expect_equal(res$exit_code, 0L)
  expect_match(res$stdout, "hello from subprocess")
})

test_that("run_job_sync reports failure for a script that errors", {
  skip_on_cran()
  run <- make_run_dir()
  script <- file.path(run$dir, "boom.R")
  writeLines("stop('kaboom')", script)
  res <- run_job_sync(script, "boom")
  expect_false(res$success)
  expect_match(res$stderr, "kaboom")
})
