# dscc.mcpserver

An [MCP](https://modelcontextprotocol.io) server that exposes the **DSCC**
multi-omics cancer subtyping method as tools over Streamable HTTP. Built on the
[`mcpserver`](https://github.com/tinnlab/mcpserver-r) R framework, modeled on
`rcpa-mcpserver`.

DSCC ("Disease Subtyping using Spectral Clustering and Community detection from
Consensus networks") integrates several omics layers into consensus similarity
networks and assigns each sample to a prognostic subtype. The core method
(`runDSCC`) and the single NEMO helper it needs (`nemo.num.clusters`) are
vendored under `inst/dscc/` with attribution; the package itself is a clean
CRAN-style R package.

## Tools

| Tool | Purpose | Elicited parameters |
|------|---------|---------------------|
| `validate_input_file` | Validate an omics matrix (features × samples) or a survival table (sample / os / isDead) | — (LLM supplies `file_type`) |
| `run_dscc_subtyping` | Run DSCC on ≥1 omics layers; returns `clusters.csv` (sample → subtype). Optional survival URL adds a Cox p-value | `max_clusters` |
| `evaluate_subtyping` | Cox PH p-value (+ optional permutation log-rank) for a clustering vs. survival | `empirical`, `n_permutations` |
| `plot_subtypes` | Kaplan-Meier or silhouette PNG | `plot_type` |

The three analysis tools are **bidirectional** and prompt an elicitation-capable
client for the parameters above when they are omitted. URLs (`*_uri`) are never
elicited — pass them exactly as provided by your platform.

### Input formats

* **Omics matrix** — CSV/TSV, *features × samples*: column 1 is the feature ID,
  the header row is sample names, the rest are numeric. NA is allowed (treated
  as 0). Transposed internally to the samples × features layout `runDSCC` needs.
* **Survival table** — CSV/TSV, one row per sample: a sample identifier (a
  `sample` column or the first column), `os` (time, ≥ 0), and `isDead` (1 =
  event, 0 = censored).

## Running locally (conda)

```bash
conda env create -f environment.yml          # creates the `dscc-mcp` env
conda run -n dscc-mcp R CMD INSTALL mcpserver_0.1.0.tar.gz
conda run -n dscc-mcp R CMD INSTALL .
conda run -n dscc-mcp Rscript inst/run-http.R # serves /mcp on :9006, results on :9007
```

## Running with Docker

```bash
docker compose up --build        # unauthenticated, /mcp on :9006, static on :9007
```

Authenticated (JWT + admin UI):

```bash
export MCPSERVER_ADMIN_TOKEN=$(openssl rand -hex 32)
docker compose -f docker-compose.yaml -f docker-compose.auth.yaml up -d --build
```

## Environment variables

`DSCC_PORT` (9006), `DSCC_STATIC_PORT` (9007), `DSCC_HOST`, `DSCC_STATIC_HOST`,
`DSCC_DAEMONS` (4), `DSCC_RESULTS_DIR`, `BASE_URL`, `DSCC_LOG`. Auth:
`DSCC_AUTH=on`, `MCPSERVER_ADMIN_TOKEN`, `DSCC_AUTH_DB`, `DSCC_AUTH_ISSUER`,
`DSCC_AUTH_AUDIENCE` (`dscc`), `DSCC_AUTH_UI`.

## Tests

```bash
conda run -n dscc-mcp Rscript -e "devtools::test()"                 # unit + dispatch + integration
DSCC_RUN_TEMPLATE_TESTS=1 conda run -n dscc-mcp Rscript -e "devtools::test()"  # + real DSCC on fixtures
conda run -n dscc-mcp R CMD check --as-cran .
```

Tier-3 template tests run real DSCC in a subprocess and are skipped unless
`DSCC_RUN_TEMPLATE_TESTS=1` is set and the scientific packages are installed, so
a clean `R CMD check` passes without them.

## Attribution

DSCC method © the tinnguyen-lab authors; `nemo.num.clusters` from
[NEMO](https://github.com/Shamir-Lab/NEMO) (Rappoport & Shamir, 2019). Both are
vendored under `inst/dscc/` for use inside the analysis subprocess.
