FROM rocker/r-ver:4.4.2

ENV DSCC_PORT=9006 \
    DSCC_STATIC_PORT=9007 \
    DSCC_DAEMONS=6 \
    DSCC_RESULTS_DIR=/var/lib/dscc/results \
    BASE_URL=http://localhost:9007 \
    DEBIAN_FRONTEND=noninteractive \
    # ---- Authentication (default off; opt-in via docker-compose.auth.yaml)
    # DSCC_AUTH=on               enable JWT auth + admin REST + admin SPA
    # MCPSERVER_ADMIN_TOKEN=...  bootstrap admin token (REQUIRED in prod)
    # DSCC_AUTH_DB=/path/db      SQLite store for users + tokens
    # DSCC_AUTH_ISSUER=...       JWT iss claim (default http://127.0.0.1:9006)
    # DSCC_AUTH_AUDIENCE=...     JWT aud claim (default dscc)
    # DSCC_AUTH_UI=off           hide the bundled /admin/ui SPA
    DSCC_AUTH=off

RUN apt-get update && apt-get install -y --no-install-recommends \
      cmake \
      libcurl4-openssl-dev libssl-dev libxml2-dev libsodium-dev \
      libgit2-dev libglpk-dev libfontconfig1-dev libfreetype6-dev \
      libharfbuzz-dev libfribidi-dev libpng-dev libtiff5-dev libjpeg-dev \
    && rm -rf /var/lib/apt/lists/*

# Framework + DSCC scientific dependencies. These come from the base image's
# pinned binary repo (fast). NEMO's nemo.num.clusters is vendored in
# inst/dscc, so no GitHub install is needed.
RUN R -e "install.packages(c('processx','httr2','jsonlite','jsonvalidate','jose','later','promises','R6','openssl','DBI','RSQLite','testthat','withr','mockery','magrittr','matrixStats','SNFtool','igraph','cluster','survival','RhpcBLASctl'))"

# mcpserver requires nanonext (>= 1.9.0) and mirai (>= 2.0.0), which are
# newer than the base image's pinned binary snapshot. Pull the current
# versions from CRAN (nanonext builds its bundled libs with cmake).
RUN R -e "install.packages(c('nanonext','mirai'), repos='https://cloud.r-project.org')" \
 && R -e "stopifnot(packageVersion('nanonext') >= '1.9.0', packageVersion('mirai') >= '2.0.0')"

COPY mcpserver_*.tar.gz /tmp/mcpserver.tar.gz
RUN R CMD INSTALL /tmp/mcpserver.tar.gz && rm /tmp/mcpserver.tar.gz

COPY . /tmp/dscc-mcpserver
RUN R CMD INSTALL /tmp/dscc-mcpserver && rm -rf /tmp/dscc-mcpserver

RUN mkdir -p /var/lib/dscc/results
VOLUME ["/var/lib/dscc/results"]

EXPOSE 9006 9007

CMD ["Rscript", "-e", "dscc.mcpserver::run_http_entrypoint()"]
