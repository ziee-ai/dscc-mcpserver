# dscc.mcpserver

[![R-CMD-check](https://github.com/ziee-ai/dscc-mcpserver/actions/workflows/R-CMD-check.yml/badge.svg)](https://github.com/ziee-ai/dscc-mcpserver/actions/workflows/R-CMD-check.yml)

An [MCP](https://modelcontextprotocol.io) server that exposes the **DSCC**
multi-omics cancer subtyping method as tools over **Streamable HTTP** or
**stdio**. Built on the [`mcpserver`](https://github.com/ziee-ai/mcpserver-r) R
framework.

DSCC ("Disease Subtyping using Spectral Clustering and Community detection from
Consensus networks") integrates several omics layers into consensus similarity
networks and assigns each sample to a prognostic subtype. The core method
(`runDSCC`) and the single NEMO helper it needs (`nemo.num.clusters`) are
vendored under `inst/dscc/` with attribution; the package itself is a clean
CRAN-style R package.

## Install

```r
install.packages("dscc.mcpserver",
                 repos = c("https://ziee-ai.github.io/drat", getOption("repos")))
```

This pulls `dscc.mcpserver` and the [`mcpserver`](https://github.com/ziee-ai/mcpserver-r)
framework from the [ziee-ai drat](https://ziee-ai.github.io/drat/); the remaining
dependencies come from CRAN (and, for the analysis tools, Bioconductor).

## Tools

| Tool | Purpose | Elicited parameters |
|------|---------|---------------------|
| `validate_input_file` | Validate an omics matrix (features × samples) or a survival table (sample / os / isDead) | — (LLM supplies `file_type`) |
| `run_dscc_subtyping` | Run DSCC on ≥1 omics layers; returns `clusters.csv` (sample → subtype). Optional survival URL adds a Cox p-value | `max_clusters` |
| `evaluate_subtyping` | Cox PH p-value (+ optional permutation log-rank) for a clustering vs. survival | `empirical`, `n_permutations` |
| `plot_subtypes` | Kaplan-Meier or silhouette PNG | `plot_type` |

The analysis tools are **bidirectional**: an elicitation-capable client is
prompted for the listed parameters when they are omitted. URLs (`*_uri`) are
never elicited — pass them exactly as your platform provides them.

## Input formats

* **Omics matrix** — CSV/TSV, *features × samples*: column 1 is the feature ID,
  the header row is sample names, the rest are numeric. NA is allowed (treated
  as 0). Transposed internally to the samples × features layout `runDSCC` needs.
* **Survival table** — CSV/TSV, one row per sample: a sample identifier (a
  `sample` column or the first column), `os` (time, ≥ 0), and `isDead` (1 =
  event, 0 = censored).

---

## Starting the server

Pick whichever fits your deployment. All four launch the **same** server; they
differ only in transport (stdio vs. Streamable HTTP) and how it is hosted.

### 1. On ziee

**a. From the MCP server hub (recommended).** Install it in one click from
ziee's curated hub:

```
{{ZIEE_URL}}/hub/mcp-servers
```

**b. Manually, as a stdio server.** Go to:

```
{{ZIEE_URL}}/settings/mcp-servers
```

In the **Add MCP Server** panel choose the **stdio** transport type, and in the
**command** field put:

```
R -e "install.packages('dscc.mcpserver', repos=c('https://ziee-ai.github.io/drat', getOption('repos'))); dscc.mcpserver::start_stdio_server()"
```

`dscc.mcpserver::start_stdio_server()` speaks the MCP **stdio** transport
(newline-delimited JSON-RPC on stdin/stdout). The one-liner above installs the
package on first launch, then starts it; once installed you can drop the
`install.packages(...)` half and use just
`R -e "dscc.mcpserver::start_stdio_server()"`. By default results are returned as
local `file://` paths and no HTTP port is opened; set `DSCC_RESULTS_MODE=http` to
start the static results server and emit `http://` links instead. `stdout` is
reserved for the protocol — diagnostics go to `stderr` (or `DSCC_LOG`).

### 2. Over HTTP with Docker

Serves the Streamable HTTP transport plus the static results server:

```bash
docker compose up --build
```

`/mcp` is served on `:9006` and result files on `:9007`. See
[Advanced setup](#advanced-setup) to enable authentication.

### 3. From R (the R interface)

Install once (see [Install](#install)), then start either transport directly:

```r
# Streamable HTTP — /mcp on :9006, static results on :9007
dscc.mcpserver::run_http_entrypoint()

# stdio — newline-delimited JSON-RPC on stdin/stdout
dscc.mcpserver::start_stdio_server()
```

Both accept arguments for ports, daemon count, and results mode — see
[Advanced setup](#advanced-setup).

### 4. With conda

A reproducible environment for the package and the `mcpserver` framework is
defined in `environment.yml` (creates the `dscc-mcp` env):

```bash
conda env create -f environment.yml
# install the mcpserver framework from the ziee-ai drat
conda run -n dscc-mcp Rscript -e 'install.packages("mcpserver", repos=c("https://ziee-ai.github.io/drat", getOption("repos")))'
conda run -n dscc-mcp R CMD INSTALL .

# HTTP transport
conda run -n dscc-mcp Rscript inst/run-http.R
# stdio transport
conda run -n dscc-mcp Rscript inst/run-stdio.R
```

---

## Advanced setup

### Configuration parameters

Every knob is an environment variable; the HTTP and stdio entry points read the
same set. **All of these are optional** — the server starts with the defaults
shown, so you only set a variable to override it.

| Env var | Required? | Default | Purpose |
|---|---|---|---|
| `DSCC_PORT` | optional | `9006` | MCP `/mcp` listen port (HTTP transport) |
| `DSCC_HOST` | optional | `0.0.0.0` | MCP bind host |
| `DSCC_STATIC_PORT` | optional | `9007` | Static results server port |
| `DSCC_STATIC_HOST` | optional | `127.0.0.1` | Static server bind host |
| `DSCC_DAEMONS` | optional | `4` | Mirai worker count |
| `DSCC_RESULTS_DIR` | optional | `tempdir()/dscc-results` | Where job output lands (auto-created on start) |
| `DSCC_RESULTS_MODE` | optional | `file` | stdio only: `file` → `file://` URIs (no HTTP server); `http` → spawn the static server and emit `http://` URIs |
| `BASE_URL` | optional | `http://localhost:9007` | URL prefix for `resource_link`s |
| `DSCC_LOG` | optional | unset → stderr | When set, redirects stderr/log to that file |

The R entry points also take these as named arguments, which override the env
vars:

```r
dscc.mcpserver::run_http_entrypoint(port = 9006, static_port = 9007, daemons = 6)
dscc.mcpserver::start_stdio_server(results = "http", daemons = 6)
```

### Authentication

Authentication is **off by default** — deployments stay unauthenticated unless
you opt in. Setting `DSCC_AUTH=on` requires a JWT on every `/mcp` request and
turns on the bundled admin REST API + admin web interface (a user-management
page served in your browser at `/admin/ui`, on the same port as `/mcp`).

> **Auth applies to the HTTP `/mcp` transport only — stdio needs no token.**
> The stdio transport (`dscc.mcpserver::start_stdio_server()`, used by the ziee
> integration and local clients) is a subprocess your client spawns directly
> over stdin/stdout; it performs no JWT auth and ignores `DSCC_AUTH`. Secure
> it with normal OS process/file permissions instead. The token flow below is
> for the HTTP transport.

Every variable below is **optional**: with `DSCC_AUTH=off` (the default) none
of them are read; once auth is on, each still has a default or is auto-created,
so the only one you should normally set yourself is `MCPSERVER_ADMIN_TOKEN`.

| Env var | Required? | Default / behavior | Purpose |
|---|---|---|---|
| `DSCC_AUTH` | optional | `off` | Master switch. Set `on` to enable JWT auth + admin API + admin web interface. |
| `MCPSERVER_ADMIN_TOKEN` | **set in production** | auto-generated if unset (logged once to stderr / `DSCC_LOG`) | Opaque bootstrap admin token. An auto-generated value does NOT survive a restart, so set it explicitly for any persistent deployment. |
| `DSCC_AUTH_DB` | optional | `<DSCC_RESULTS_DIR>/auth.db` (auto-created) | SQLite store for users + tokens. Mount a persistent volume here in production. |
| `DSCC_AUTH_ISSUER` | optional | `http://127.0.0.1:<DSCC_PORT>` (derived) | JWT `iss` claim. |
| `DSCC_AUTH_AUDIENCE` | optional | `dscc` | JWT `aud` claim. |
| `DSCC_AUTH_UI` | optional | `on` | Set `off` to hide the bundled `/admin/ui` web interface (REST API stays up). |

Enabling auth requires the `DBI` and `RSQLite` R packages
(`install.packages(c("DBI", "RSQLite"))`).

#### Turn on auth with Docker

The repo ships an overlay that enables auth and mounts a named volume so the
SQLite store survives restarts:

```bash
export MCPSERVER_ADMIN_TOKEN=$(openssl rand -hex 32)
docker compose -f docker-compose.yaml -f docker-compose.auth.yaml up -d --build
```

The overlay **requires** `MCPSERVER_ADMIN_TOKEN` to be set and fails fast with a
clear error if it is not — so production never launches with an ephemeral token.

#### Turn on auth from R / conda

```bash
export DSCC_AUTH=on
export MCPSERVER_ADMIN_TOKEN=$(openssl rand -hex 32)
export DSCC_AUTH_DB=/var/lib/dscc/auth.db   # persistent path
conda run -n dscc-mcp Rscript inst/run-http.R
```

### Bootstrap the first admin (first run)

The **bootstrap admin token** is the root credential — it is how you get your
first admin account without there being a user in the database yet.

**Create a bootstrap admin token.** It is just a long, high-entropy opaque
string — generate one however you like and keep it secret:

```bash
openssl rand -hex 32                              # 64 hex chars (recommended)
# alternatives:
python3 -c "import secrets; print(secrets.token_hex(32))"
head -c 32 /dev/urandom | base64                  # any high-entropy string works
```

Then:

1. **Set it before the first start** and export it as `MCPSERVER_ADMIN_TOKEN`
   (`export MCPSERVER_ADMIN_TOKEN=<the value>`), or pass it via your compose
   `.env` / secret manager. If you skip this, the server auto-generates one and
   logs it **once** to stderr / `DSCC_LOG` — fine for a quick local test, but
   it is lost on restart, so set it explicitly for anything persistent.
2. **Start the server with `DSCC_AUTH=on`** (see above). On first start it
   auto-creates the SQLite store at `DSCC_AUTH_DB`.
3. The bootstrap token now authenticates against the admin REST API and the
   admin UI as a full admin. Use it to create real user accounts and mint their
   tokens (below). Treat it like a root password — rotate it by changing
   `MCPSERVER_ADMIN_TOKEN` and restarting.

### Access the user-management UI

With auth on, open the bundled admin web interface in a browser:

```
http://localhost:9006/admin/ui
```

Log in with your `MCPSERVER_ADMIN_TOKEN`. The UI lists users and lets you
create, edit, and delete them, and mint or revoke their tokens. (To disable the
web interface, set `DSCC_AUTH_UI=off`; the REST API under `/admin/*` stays
available.)

### Create a user and mint a token

**Via the UI:** create a user, open their **Tokens** tab, and click mint. The
JWT is shown **once** in a modal — copy it immediately. Clients then send it as
`Authorization: Bearer <jwt>` on every `/mcp` request.

**Via the REST API** (same `/admin/*` surface the UI uses; authenticate with the
bootstrap token or an admin user's JWT):

```bash
ADMIN=$MCPSERVER_ADMIN_TOKEN
BASE=http://localhost:9006

# 1. create a user
curl -s -X POST $BASE/admin/users \
  -H "Authorization: Bearer $ADMIN" -H 'Content-Type: application/json' \
  -d '{"username":"alice","is_admin":false}'
# -> {"id":"<user_id>", ...}

# 2. mint a token for that user (ttl in seconds; capped at 1 year)
curl -s -X POST $BASE/admin/tokens/mint \
  -H "Authorization: Bearer $ADMIN" -H 'Content-Type: application/json' \
  -d '{"user_id":"<user_id>","name":"laptop","ttl":2592000}'
# -> {"jti":"...","token":"<jwt>","expires_at":...}   (the JWT is the "token" field, returned once)

# 3. the client now calls /mcp with that JWT
curl -s $BASE/mcp -H "Authorization: Bearer <jwt>" ...
```

Admin REST routes: `GET /admin/healthz`, `GET|POST /admin/users`,
`GET|PATCH|DELETE /admin/users/{id}`, `GET /admin/users/{id}/tokens`,
`POST /admin/tokens/mint`, `POST /admin/tokens/{jti}/revoke`,
`POST /admin/tokens/{jti}/reactivate`, `DELETE /admin/tokens/{jti}`.

> **Note:** the static results server (port `9007`) is **not** behind
> the JWT. Its `resource_link` URLs are unguessable but not access-controlled —
> put a reverse proxy in front of it if you need per-user control over outputs.

### Full-parameter launch examples

The three examples below start the **HTTP transport** with *every* knob set
explicitly — the configuration variables plus authentication. They are
equivalent: the same env-var contract, just delivered differently. Drop the
`DSCC_AUTH*` / `MCPSERVER_ADMIN_TOKEN` lines to run unauthenticated.

> **How the env vars are read.** Most variables are read when the server
> starts. Two of them — `DSCC_RESULTS_DIR` and `BASE_URL` — are read **once,
> when the package is loaded** (`.onLoad`), so they must already be set *before*
> the package loads. With Docker and conda this is automatic (the variables are
> in the environment before the R process starts); in an interactive R session
> set them with `Sys.setenv()` **before** `library(dscc.mcpserver)` (shown below).

#### Docker — full parameters

```bash
docker build -t dscc.mcpserver:latest .

export MCPSERVER_ADMIN_TOKEN=$(openssl rand -hex 32)
echo "admin token (needed to log into /admin/ui): $MCPSERVER_ADMIN_TOKEN"

docker run -d --name dscc.mcpserver \
  -p 9006:9006 -p 9007:9007 \
  -v dscc-results:/var/lib/dscc/results \
  -v dscc-auth:/var/lib/dscc/auth \
  `# --- configuration ---` \
  -e DSCC_PORT=9006 \
  -e DSCC_HOST=0.0.0.0 \
  -e DSCC_STATIC_PORT=9007 \
  -e DSCC_STATIC_HOST=0.0.0.0 \
  -e DSCC_DAEMONS=6 \
  -e DSCC_RESULTS_DIR=/var/lib/dscc/results \
  -e BASE_URL=http://localhost:9007 \
  -e DSCC_LOG=/var/log/dscc.log \
  `# --- authentication ---` \
  -e DSCC_AUTH=on \
  -e MCPSERVER_ADMIN_TOKEN="$MCPSERVER_ADMIN_TOKEN" \
  -e DSCC_AUTH_DB=/var/lib/dscc/auth/auth.db \
  -e DSCC_AUTH_ISSUER=https://dscc.example.com \
  -e DSCC_AUTH_AUDIENCE=dscc \
  -e DSCC_AUTH_UI=on \
  dscc.mcpserver:latest
```

`DSCC_STATIC_HOST=0.0.0.0` is required so the static results port is
reachable from outside the container. Set `BASE_URL` (and
`DSCC_AUTH_ISSUER`) to the host's externally reachable URL in a real
deployment, not `localhost`.

#### R interface — full parameters

```r
# RESULTS_DIR and BASE_URL must be set BEFORE the package loads (.onLoad reads
# them once), so call Sys.setenv() before library().
Sys.setenv(
  # --- configuration ---
  DSCC_PORT        = "9006",
  DSCC_HOST        = "0.0.0.0",
  DSCC_STATIC_PORT = "9007",
  DSCC_STATIC_HOST = "0.0.0.0",
  DSCC_DAEMONS     = "6",
  DSCC_RESULTS_DIR = "/var/lib/dscc/results",
  BASE_URL         = "http://localhost:9007",
  DSCC_LOG         = "/var/log/dscc.log",
  # --- authentication ---
  DSCC_AUTH             = "on",
  MCPSERVER_ADMIN_TOKEN = "replace-with-openssl-rand-hex-32",
  DSCC_AUTH_DB          = "/var/lib/dscc/auth/auth.db",
  DSCC_AUTH_ISSUER      = "https://dscc.example.com",
  DSCC_AUTH_AUDIENCE    = "dscc",
  DSCC_AUTH_UI          = "on"
)

library(dscc.mcpserver)

# Ports / static port / daemon count can come from the env vars above, or be
# passed explicitly as arguments (arguments win over the env vars):
run_http_entrypoint(port = 9006, static_port = 9007, daemons = 6)
```

#### conda — full parameters

```bash
export MCPSERVER_ADMIN_TOKEN=$(openssl rand -hex 32)
echo "admin token (needed to log into /admin/ui): $MCPSERVER_ADMIN_TOKEN"

# --- configuration ---
export DSCC_PORT=9006
export DSCC_HOST=0.0.0.0
export DSCC_STATIC_PORT=9007
export DSCC_STATIC_HOST=0.0.0.0
export DSCC_DAEMONS=6
export DSCC_RESULTS_DIR=/var/lib/dscc/results
export BASE_URL=http://localhost:9007
export DSCC_LOG=/var/log/dscc.log
# --- authentication ---
export DSCC_AUTH=on
export DSCC_AUTH_DB=/var/lib/dscc/auth/auth.db
export DSCC_AUTH_ISSUER=https://dscc.example.com
export DSCC_AUTH_AUDIENCE=dscc
export DSCC_AUTH_UI=on

# the exported environment is inherited by the R process, so .onLoad sees it
conda run -n dscc-mcp Rscript inst/run-http.R
```

For the **stdio** transport, the relevant knobs are fewer —
`DSCC_RESULTS_MODE` (`file` default, or `http`), `DSCC_DAEMONS`,
`DSCC_RESULTS_DIR`, `DSCC_LOG` (plus `DSCC_STATIC_PORT` /
`DSCC_STATIC_HOST` / `BASE_URL` only when `DSCC_RESULTS_MODE=http`).
Export them the same way, then run `Rscript inst/run-stdio.R` (or
`dscc.mcpserver::start_stdio_server()`). Authentication does not apply to stdio.

---

## Tests

```bash
conda run -n dscc-mcp Rscript -e 'testthat::test_local(".")'   # unit + dispatch + integration
conda run -n dscc-mcp R CMD check --as-cran .
```

Tier-3 template tests run real DSCC in a subprocess and are skipped unless
`DSCC_RUN_TEMPLATE_TESTS=1` is set and the scientific packages are installed, so
a clean `R CMD check` passes without them:

```bash
DSCC_RUN_TEMPLATE_TESTS=1 conda run -n dscc-mcp Rscript -e 'testthat::test_local(".")'
```

## Attribution / License

Licensed under **MIT** (see `LICENSE`).

DSCC method © the tinnguyen-lab authors; `nemo.num.clusters` from
[NEMO](https://github.com/Shamir-Lab/NEMO) (Rappoport & Shamir, 2019). Both are
vendored under `inst/dscc/` for use inside the analysis subprocess.
