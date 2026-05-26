#!/usr/bin/env bash
# Smoke-test the Docker container:
#  1. Start the container, wait for the MCP server to come up
#  2. POST initialize -> assert serverInfo.name = dscc-mcpserver
#  3. POST tools/list -> assert all 4 tools advertised
#  4. POST tools/call validate_input_file with an in-container CSV ->
#     assert isError = false and n_features correct
#  5. /admin/* must NOT be mounted with auth off
#  6. Static server serves /results/
#  7. Run real run_dscc_subtyping on the bundled fixtures; download clusters.csv
#  8. Stop the container
#
# Usage:
#   tests/protocol/docker-smoke.sh                 # uses dscc-mcpserver:test
#   tests/protocol/docker-smoke.sh my-image:tag    # override image tag

set -euo pipefail

IMAGE="${1:-dscc-mcpserver:test}"
CTR=dscc-mcpserver-smoke
PORT=$(shuf -i 30000-50000 -n 1)
STATIC_PORT=$(shuf -i 30000-50000 -n 1)

echo "[smoke] starting container $CTR (image=$IMAGE, port=$PORT, static=$STATIC_PORT)"
docker rm -f "$CTR" >/dev/null 2>&1 || true
docker run -d --name "$CTR" \
  -e DSCC_HOST=0.0.0.0 \
  -e DSCC_STATIC_HOST=0.0.0.0 \
  -e DSCC_ALLOW_LOCAL_URIS=TRUE \
  -p "${PORT}:9006" \
  -p "${STATIC_PORT}:9007" \
  "$IMAGE"

echo "[smoke] waiting for /mcp to accept initialize..."
for i in $(seq 1 90); do
  status=$(curl -s -o /dev/null -w '%{http_code}' \
    --connect-timeout 1 --max-time 3 \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -H 'Origin: http://localhost' \
    -X POST "http://localhost:${PORT}/mcp" \
    -d '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"probe","version":"0"},"capabilities":{}}}' \
    || echo 000)
  if [ "$status" = "200" ]; then
    echo "[smoke] server up after ${i}s (HTTP $status)"
    break
  fi
  if [ "$i" = "90" ]; then
    echo "[smoke] server did not come up after 90s (last HTTP $status); container logs:"
    docker logs "$CTR" 2>&1 | tail -40
    exit 1
  fi
  sleep 1
done

SID_FILE=$(mktemp)
trap 'rm -f "$SID_FILE"; docker rm -f "$CTR" >/dev/null 2>&1 || true' EXIT

post() {
  local body="$1"
  local sid=""
  [ -s "$SID_FILE" ] && sid=$(cat "$SID_FILE")
  if [ -n "$sid" ]; then
    curl -s --max-time 240 -X POST "http://localhost:${PORT}/mcp" \
      -H 'Content-Type: application/json' \
      -H 'Accept: application/json, text/event-stream' \
      -H 'Origin: http://localhost' \
      -H "Mcp-Session-Id: ${sid}" \
      -d "$body"
  else
    curl -s --max-time 240 -X POST "http://localhost:${PORT}/mcp" \
      -H 'Content-Type: application/json' \
      -H 'Accept: application/json, text/event-stream' \
      -H 'Origin: http://localhost' \
      -d "$body"
  fi
}

post_capture_session() {
  local body="$1"
  local headers_file
  headers_file=$(mktemp)
  local resp
  resp=$(curl -s -D "$headers_file" -X POST "http://localhost:${PORT}/mcp" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -H 'Origin: http://localhost' \
    -d "$body")
  awk 'tolower($1) == "mcp-session-id:" { gsub(/\r/, ""); print $2; exit }' \
    "$headers_file" > "$SID_FILE"
  rm -f "$headers_file"
  echo "$resp"
}

echo "[smoke] step 1: initialize (captures Mcp-Session-Id)"
init=$(post_capture_session '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"smoke","version":"0"},"capabilities":{}}}')
echo "$init" | jq -e '.result.serverInfo.name == "dscc-mcpserver"' >/dev/null
echo "[smoke]   OK: serverInfo.name = dscc-mcpserver, session=$(cat "$SID_FILE")"

echo "[smoke] step 2: tools/list"
tools=$(post '{"jsonrpc":"2.0","id":2,"method":"tools/list"}')
names=$(echo "$tools" | jq -r '.result.tools[].name' | sort | tr '\n' ' ')
expected="evaluate_subtyping plot_subtypes run_dscc_subtyping validate_input_file"
if [ "$(echo $names | xargs)" != "$expected" ]; then
  echo "[smoke]   FAIL: tools mismatch"
  echo "         expected: $expected"
  echo "         got:      $names"
  exit 1
fi
echo "[smoke]   OK: 4 tools listed"

echo "[smoke] step 3: write an omics CSV inside the container and validate it"
docker exec "$CTR" sh -c 'printf "\"\",\"s1\",\"s2\"\n\"g1\",1,2\n\"g2\",3,4\n\"g3\",5,6\n" > /tmp/smoke.csv'
call=$(post '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"validate_input_file","arguments":{"file_uri":"file:///tmp/smoke.csv","file_type":"omics_matrix"}}}')
is_err=$(echo "$call" | jq -r '.result.isError // false')
if [ "$is_err" = "true" ]; then
  echo "[smoke]   FAIL: validate_input_file returned isError=true"
  echo "$call" | jq .
  exit 1
fi
n_features=$(echo "$call" | jq -r '.result.content[0].text' | jq -r '.n_features')
if [ "$n_features" != "3" ]; then
  echo "[smoke]   FAIL: expected n_features=3, got n_features=$n_features"
  echo "$call" | jq .
  exit 1
fi
echo "[smoke]   OK: validate_input_file returned n_features=3"

echo "[smoke] step 4: admin surface MUST NOT be mounted in default (auth off) mode"
admin_healthz=$(curl -s -o /dev/null -w '%{http_code}' \
  --max-time 3 -H 'Origin: http://localhost' \
  "http://localhost:${PORT}/admin/healthz" || echo 000)
if [ "$admin_healthz" = "200" ]; then
  echo "[smoke]   FAIL: /admin/healthz returned 200 with DSCC_AUTH=off"
  exit 1
fi
echo "[smoke]   OK: /admin/healthz returns ${admin_healthz} (not 200)"

echo "[smoke] step 5: static server serves /results/"
docker exec "$CTR" sh -c 'mkdir -p /var/lib/dscc/results/smoke && echo "hello" > /var/lib/dscc/results/smoke/hi.txt'
content=$(curl -s "http://localhost:${STATIC_PORT}/results/smoke/hi.txt")
if [ "$content" != "hello" ]; then
  echo "[smoke]   FAIL: static server did not return file content (got: $content)"
  exit 1
fi
echo "[smoke]   OK: static server returned the file"

echo "[smoke] step 6: run real DSCC subtyping on the bundled fixtures"
docker cp inst/fixtures/omics1.csv "$CTR:/tmp/omics1.csv"
docker cp inst/fixtures/omics2.csv "$CTR:/tmp/omics2.csv"
sub=$(post '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"run_dscc_subtyping","arguments":{"omics_uris":["file:///tmp/omics1.csv","file:///tmp/omics2.csv"],"max_clusters":6}}}')
is_err=$(echo "$sub" | jq -r '.result.isError // false')
if [ "$is_err" = "true" ]; then
  echo "[smoke]   FAIL: run_dscc_subtyping returned isError"
  echo "$sub" | jq -r '.result.content[0].text'
  exit 1
fi
result_type=$(echo "$sub" | jq -r '.result.content[0].text' | jq -r '.result_type')
if [ "$result_type" != "dscc_subtyping" ]; then
  echo "[smoke]   FAIL: expected result_type=dscc_subtyping, got $result_type"
  echo "$sub" | jq .
  exit 1
fi
csv_url=$(echo "$sub" | jq -r '.result.content[1].uri')
echo "[smoke]   OK: subtyping produced $csv_url"

echo "[smoke] step 7: download clusters.csv via static server"
csv_path=$(echo "$csv_url" | sed 's|.*/results/|results/|')
status=$(curl -s -o /tmp/clusters.csv -w '%{http_code}' "http://localhost:${STATIC_PORT}/${csv_path}")
if [ "$status" != "200" ]; then
  echo "[smoke]   FAIL: download returned HTTP $status"
  exit 1
fi
header=$(head -1 /tmp/clusters.csv)
echo "$header" | grep -q "sample" || { echo "[smoke]   FAIL: missing sample column"; exit 1; }
echo "$header" | grep -q "cluster" || { echo "[smoke]   FAIL: missing cluster column"; exit 1; }
n_lines=$(wc -l < /tmp/clusters.csv)
rm -f /tmp/clusters.csv
echo "[smoke]   OK: clusters.csv ($n_lines lines) has sample + cluster columns"

echo "[smoke] all checks passed"
