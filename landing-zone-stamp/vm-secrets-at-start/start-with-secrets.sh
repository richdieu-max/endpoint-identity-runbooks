#!/usr/bin/env bash
# /opt/app/bin/start-with-secrets.sh  (SKELETON)
#
# 1. Ask the Instance Metadata Service (IMDS) for a token for Key Vault, using
#    the VM's system-assigned identity. No credential is stored on the VM.
# 2. Read each secret named in /etc/app/app.conf through the vault's private
#    endpoint (the vault has public access disabled).
# 3. Export them and exec the app, so they live only in the process environment.
#
# Rotating a secret = update it in Key Vault, then: systemctl restart app
# The VM identity holds "Key Vault Secrets User": it can read, never write.
set -euo pipefail
set +x  # never trace: traces would print secret values

CONF="${APP_CONF:-/etc/app/app.conf}"
APP_BIN="${APP_BIN:-/opt/app/bin/app}"
IMDS="http://169.254.169.254/metadata/identity/oauth2/token"
KV_API="7.4"

# shellcheck source=/dev/null
. "$CONF"
: "${VAULT_NAME:?VAULT_NAME missing in $CONF}"
: "${SECRET_MAP:?SECRET_MAP missing in $CONF}"

log() { logger -t app-secrets -- "$*" 2>/dev/null || echo "app-secrets: $*" >&2; }

get_token() {
  curl -sS --fail --max-time 10 -H "Metadata: true" \
    "${IMDS}?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net" \
    | jq -r '.access_token'
}

get_secret() {
  local token="$1" name="$2"
  curl -sS --fail --max-time 10 -H "Authorization: Bearer ${token}" \
    "https://${VAULT_NAME}.vault.azure.net/secrets/${name}?api-version=${KV_API}" \
    | jq -r '.value'
}

token="$(get_token)" || { log "could not get a token from IMDS"; exit 1; }
[ -n "$token" ] && [ "$token" != "null" ] || { log "empty token from IMDS"; exit 1; }

count=0
for pair in $SECRET_MAP; do
  env_name="${pair%%=*}"
  secret_name="${pair#*=}"
  value="$(get_secret "$token" "$secret_name")" || { log "could not read secret '${secret_name}'"; exit 1; }
  if [ -z "$value" ] || [ "$value" = "null" ]; then
    log "secret '${secret_name}' is empty"; exit 1
  fi
  export "${env_name}=${value}"
  count=$((count + 1))
done
unset token value

log "loaded ${count} secret(s) from ${VAULT_NAME}; starting app"
exec "$APP_BIN"
