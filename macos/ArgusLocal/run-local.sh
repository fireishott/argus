#!/bin/bash
set -euo pipefail

APP_SUPPORT="$HOME/Library/Application Support/Argus"
REPO_DEFAULT="$HOME/Developer/Argus"
REPO="${ARGUS_REPO_DIR:-$REPO_DEFAULT}"
CONFIG="$APP_SUPPORT/config.yaml"
ENV_FILE="$APP_SUPPORT/runtime.env"

mkdir -p "$APP_SUPPORT"
chmod 700 "$APP_SUPPORT"

if [[ ! -f "$CONFIG" ]]; then
  cat > "$CONFIG" <<'YAML'
server:
  host: 127.0.0.1
  port: 8090
  cors_origins: []
refresh:
  cache_seconds: 30
local_first:
  keychain_credentials: true
sources:
  router:
    enabled: false
    url: ''
    password_env: ''
  usage_store:
    enabled: false
    sqlite_path: ''
  providers:
    claude: { enabled: false, credential_env: ARGUS_CLAUDE_TOKEN }
    deepseek: { enabled: true, credential_env: ARGUS_DEEPSEEK_API_KEY }
    minimax: { enabled: true, credential_env: ARGUS_MINIMAX_API_KEY }
    openrouter: { enabled: true, credential_env: ARGUS_OPENROUTER_API_KEY }
    opencode-go: { enabled: true, credential_env: ARGUS_OPENCODE_GO_API_KEY }
    xiaomi-tokenplan: { enabled: false, credential_env: ARGUS_MIMO_SESSION_COOKIE }
api:
  bearer_token_env: ''
  expose_internal_endpoints: false
  redaction: strict
integrations:
  kallisti:
    enabled: true
    snapshot_path: /api/v1/snapshot
    health_path: /api/v1/health
    minimum_schema_version: 1
    polling_seconds: 60
    alert_threshold_percent: 15
    dashboard_url: ''
logging:
  level: INFO
  redact_errors: true
YAML
  chmod 600 "$CONFIG"
fi

# Only the service process reads the secrets. Values never appear in logs or API responses.
: > "$ENV_FILE"
chmod 600 "$ENV_FILE"
for pair in \
  'openrouter:ARGUS_OPENROUTER_API_KEY' \
  'deepseek:ARGUS_DEEPSEEK_API_KEY' \
  'minimax:ARGUS_MINIMAX_API_KEY' \
  'opencode-go:ARGUS_OPENCODE_GO_API_KEY' \
  'claude:ARGUS_CLAUDE_TOKEN' \
  'router-password:ARGUS_ROUTER_PASSWORD'; do
  account="${pair%%:*}"
  variable="${pair##*:}"
  if value=$(/usr/bin/security find-generic-password -s 'Argus.Provider' -a "$account" -w 2>/dev/null); then
    printf '%s=%s\n' "$variable" "$value" >> "$ENV_FILE"
  fi
done

cd "$REPO"
export ARGUS_CONFIG="$CONFIG"
set -a
source "$ENV_FILE"
set +a
exec "$REPO/.venv/bin/python" main.py --host 127.0.0.1 --port 8090
