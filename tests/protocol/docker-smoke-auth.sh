#!/usr/bin/env bash
# Smoke-test the Docker container with DSCC_AUTH=on:
#
#   1. Start the container with the auth overlay; wait for /admin/healthz
#   2. Verify /mcp WITHOUT a bearer is 401 + WWW-Authenticate: Bearer
#   3. POST /admin/users (bootstrap) -> capture user id
#   4. POST /admin/tokens/mint -> capture JWT
#   5. POST /mcp initialize + tools/list WITH the JWT -> 200, 4 tools
#   6. POST /admin/tokens/{jti}/revoke -> 204
#   7. Same JWT on /mcp -> 401
#   8. Restart with the same volume; previously-created user persists
#
# Usage:
#   tests/protocol/docker-smoke-auth.sh                  # uses dscc-mcpserver:test
#   tests/protocol/docker-smoke-auth.sh my-image:tag

set -euo pipefail

IMAGE="${1:-dscc-mcpserver:test}"
PROJECT="dscc-mcpserver-smoke-auth"
PORT=$(shuf -i 30000-50000 -n 1)
STATIC_PORT=$(shuf -i 30000-50000 -n 1)
TOKEN=$(openssl rand -hex 32)

WORKDIR=$(mktemp -d)
trap 'docker compose -p "$PROJECT" -f "$WORKDIR/compose.yaml" down -v >/dev/null 2>&1 || true; rm -rf "$WORKDIR"' EXIT

cat > "$WORKDIR/compose.yaml" <<EOF
services:
  dscc-mcpserver:
    image: "$IMAGE"
    ports:
      - "${PORT}:9006"
      - "${STATIC_PORT}:9007"
    environment:
      DSCC_PORT: "9006"
      DSCC_STATIC_PORT: "9007"
      DSCC_HOST: "0.0.0.0"
      DSCC_STATIC_HOST: "0.0.0.0"
      DSCC_AUTH: "on"
      MCPSERVER_ADMIN_TOKEN: "$TOKEN"
      DSCC_AUTH_DB: "/var/lib/dscc/auth/auth.db"
      DSCC_ALLOW_LOCAL_URIS: "TRUE"
    volumes:
      - dscc-auth:/var/lib/dscc/auth
volumes:
  dscc-auth:
EOF

docker compose -p "$PROJECT" -f "$WORKDIR/compose.yaml" up -d
echo "[smoke-auth] waiting for /admin/healthz..."
for i in $(seq 1 90); do
  status=$(curl -s -o /dev/null -w '%{http_code}' \
    --max-time 3 -H "Authorization: Bearer $TOKEN" \
    -H 'Origin: http://localhost' \
    "http://localhost:${PORT}/admin/healthz" || echo 000)
  if [ "$status" = "200" ]; then
    echo "[smoke-auth] server up after ${i}s"
    break
  fi
  if [ "$i" = "90" ]; then
    echo "[smoke-auth] server did not come up after 90s (last HTTP $status); logs:"
    docker compose -p "$PROJECT" -f "$WORKDIR/compose.yaml" logs --tail 80
    exit 1
  fi
  sleep 1
done

echo "[smoke-auth] step 2: /mcp without bearer must 401"
hdrs=$(mktemp)
status=$(curl -s -D "$hdrs" -o /dev/null -w '%{http_code}' \
  -X POST -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -H 'Origin: http://localhost' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' \
  "http://localhost:${PORT}/mcp")
if [ "$status" != "401" ]; then
  echo "[smoke-auth]   FAIL: expected 401, got $status"
  exit 1
fi
www=$(awk 'tolower($1)=="www-authenticate:" {gsub(/\r/,""); $1=""; sub(/^ /,""); print; exit}' "$hdrs")
if ! echo "$www" | grep -qi "Bearer"; then
  echo "[smoke-auth]   FAIL: missing WWW-Authenticate: Bearer (got: $www)"
  exit 1
fi
rm -f "$hdrs"
echo "[smoke-auth]   OK: 401 + WWW-Authenticate: $www"

echo "[smoke-auth] step 3: create user via /admin/users"
uname="alice-$$"
create=$(curl -s -X POST "http://localhost:${PORT}/admin/users" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -H 'Origin: http://localhost' \
  -d "{\"username\":\"$uname\"}")
uid=$(echo "$create" | jq -r '.id')
if [ -z "$uid" ] || [ "$uid" = "null" ]; then
  echo "[smoke-auth]   FAIL: no user id; body=$create"
  exit 1
fi
echo "[smoke-auth]   OK: created user $uid"

echo "[smoke-auth] step 4: mint a JWT"
mint=$(curl -s -X POST "http://localhost:${PORT}/admin/tokens/mint" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -H 'Origin: http://localhost' \
  -d "{\"user_id\":\"$uid\",\"name\":\"smoke\",\"scopes\":[],\"ttl\":600}")
jti=$(echo "$mint" | jq -r '.jti')
jwt=$(echo "$mint" | jq -r '.token')
if [ -z "$jwt" ] || ! echo "$jwt" | grep -q '^eyJ'; then
  echo "[smoke-auth]   FAIL: no JWT in mint response; body=$mint"
  exit 1
fi
echo "[smoke-auth]   OK: minted jti=$jti"

echo "[smoke-auth] step 5: /mcp WITH the JWT"
hdrs=$(mktemp)
init=$(curl -s -D "$hdrs" -X POST "http://localhost:${PORT}/mcp" \
  -H "Authorization: Bearer $jwt" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -H 'Origin: http://localhost' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{}}}')
sid=$(awk 'tolower($1)=="mcp-session-id:" {gsub(/\r/,""); print $2; exit}' "$hdrs")
rm -f "$hdrs"
if [ -z "$sid" ]; then
  echo "[smoke-auth]   FAIL: no Mcp-Session-Id; body=$init"
  exit 1
fi
tools=$(curl -s -X POST "http://localhost:${PORT}/mcp" \
  -H "Authorization: Bearer $jwt" \
  -H "Mcp-Session-Id: $sid" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -H 'Origin: http://localhost' \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}')
n_tools=$(echo "$tools" | jq -r '.result.tools | length')
if [ "$n_tools" != "4" ]; then
  echo "[smoke-auth]   FAIL: expected 4 tools, got $n_tools"
  echo "$tools" | jq .
  exit 1
fi
echo "[smoke-auth]   OK: 4 tools listed under JWT auth"

echo "[smoke-auth] step 6: revoke the JWT"
rv_status=$(curl -s -o /dev/null -w '%{http_code}' \
  -X POST "http://localhost:${PORT}/admin/tokens/${jti}/revoke" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Origin: http://localhost')
if [ "$rv_status" != "204" ]; then
  echo "[smoke-auth]   FAIL: expected 204 from revoke, got $rv_status"
  exit 1
fi
echo "[smoke-auth]   OK: revoke returned 204"

echo "[smoke-auth] step 7: revoked JWT must be 401"
dead=$(curl -s -o /dev/null -w '%{http_code}' \
  -X POST "http://localhost:${PORT}/mcp" \
  -H "Authorization: Bearer $jwt" \
  -H "Mcp-Session-Id: $sid" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -H 'Origin: http://localhost' \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/list"}')
if [ "$dead" != "401" ]; then
  echo "[smoke-auth]   FAIL: expected 401 after revoke, got $dead"
  exit 1
fi
echo "[smoke-auth]   OK: revoked JWT returns 401"

echo "[smoke-auth] step 8: restart container; previously-created user must persist"
docker compose -p "$PROJECT" -f "$WORKDIR/compose.yaml" stop >/dev/null
docker compose -p "$PROJECT" -f "$WORKDIR/compose.yaml" up -d >/dev/null
for i in $(seq 1 60); do
  status=$(curl -s -o /dev/null -w '%{http_code}' \
    --max-time 3 -H "Authorization: Bearer $TOKEN" \
    -H 'Origin: http://localhost' \
    "http://localhost:${PORT}/admin/healthz" || echo 000)
  if [ "$status" = "200" ]; then break; fi
  sleep 1
done
list=$(curl -s -H "Authorization: Bearer $TOKEN" -H 'Origin: http://localhost' \
  "http://localhost:${PORT}/admin/users")
found=$(echo "$list" | jq -r --arg u "$uname" '.users[] | select(.username == $u) | .id')
if [ -z "$found" ]; then
  echo "[smoke-auth]   FAIL: user '$uname' did not survive restart; list=$list"
  exit 1
fi
echo "[smoke-auth]   OK: user '$uname' persisted (id=$found)"

echo "[smoke-auth] all checks passed"
