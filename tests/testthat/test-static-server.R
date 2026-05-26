test_that("guess_mime maps known extensions correctly", {
  expect_equal(guess_mime("x.csv"), "text/csv")
  expect_equal(guess_mime("x.png"), "image/png")
  expect_equal(guess_mime("x.json"), "application/json")
  expect_equal(guess_mime("x.tsv"), "text/tab-separated-values")
  expect_equal(guess_mime("x.rds"), "application/octet-stream")
  expect_equal(guess_mime("x.unknown"), "application/octet-stream")
})

test_that("spawn_static_server is exported and callable", {
  skip_if_not_installed("nanonext")
  # Full HTTP serving is exercised in the Docker smoke test; here we just
  # confirm the entry point exists.
  expect_true(is.function(spawn_static_server))
})
