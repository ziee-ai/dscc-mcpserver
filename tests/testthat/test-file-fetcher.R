test_that("is_safe_uri accepts http(s) and rejects file/data", {
  expect_true(is_safe_uri("http://example.com/x.csv"))
  expect_true(is_safe_uri("https://example.com/x.csv"))
  expect_false(is_safe_uri("file:///tmp/x.csv"))
  expect_false(is_safe_uri("data:text/csv;base64,AAAA"))
  expect_false(is_safe_uri(c("http://a", "http://b")))
})

test_that("is_local_file_uri detects file:// URIs", {
  expect_true(is_local_file_uri("file:///tmp/x.csv"))
  expect_false(is_local_file_uri("http://example.com"))
})

test_that("fetch_to_tempfile copies a local file when local URIs are allowed", {
  withr::local_envvar(DSCC_ALLOW_LOCAL_URIS = "TRUE")
  src <- write_omics_csv()
  withr::defer(unlink(src))
  out <- fetch_to_tempfile(file_uri(src))
  withr::defer(unlink(out))
  expect_true(file.exists(out))
  expect_false(identical(normalizePath(out), normalizePath(src)))
  expect_equal(readLines(out), readLines(src))
})

test_that("fetch_to_tempfile refuses file:// when local URIs are not allowed", {
  withr::local_envvar(DSCC_ALLOW_LOCAL_URIS = "FALSE")
  expect_error(fetch_to_tempfile("file:///tmp/nope.csv"),
               "only http\\(s\\) URLs are allowed")
})

test_that("fetch_to_tempfile rejects non-http schemes", {
  withr::local_envvar(DSCC_ALLOW_LOCAL_URIS = "FALSE")
  expect_error(fetch_to_tempfile("ftp://example.com/x.csv"),
               "only http\\(s\\) URLs are allowed")
})
