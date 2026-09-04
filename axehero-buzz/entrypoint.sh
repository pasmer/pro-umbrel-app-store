#!/usr/bin/env bash
#
# Buzz relay bootstrap for umbrelOS (AxeHero App Store).
#
# Responsibilities, in order:
#   1. Create ${APP_DATA_DIR}/config/buzz.env on first boot with freshly
#      generated secrets (relay signing key + git webhook HMAC).
#   2. Source that file so the user can edit it without touching the compose.
#   3. Derive every URL-shaped setting from a single BUZZ_PUBLIC_HOST value,
#      because the relay treats the RELAY_URL host as the community identity
#      (see buzz_core::tenant::relay_url_authority) — getting these out of
#      sync silently seeds a second, empty community.
#   4. Accept RELAY_OWNER_PUBKEY as either npub1... or 64-char hex.
#   5. Pass the optional BUZZ_PAIRING_RELAY_URL through to the relay.
#   6. exec buzz-relay.
#
# Everything here is idempotent: the config file is written once and never
# overwritten, so an app update never clobbers the operator's settings.

set -euo pipefail

CONFIG_DIR="${BUZZ_CONFIG_DIR:-/config}"
CONFIG_FILE="${CONFIG_DIR}/buzz.env"

log() { printf '[buzz-bootstrap] %s\n' "$*" >&2; }

banner() {
  local line
  printf '\n' >&2
  printf '  ┌───────────────────────────────────────────────────────────────┐\n' >&2
  while IFS= read -r line; do
    printf '  │ %-61s │\n' "${line}" >&2
  done
  printf '  └───────────────────────────────────────────────────────────────┘\n\n' >&2
}

# ── Secret generation ───────────────────────────────────────────────────────
# openssl ships in the runtime image; /dev/urandom is the fallback so this
# script keeps working if upstream ever slims the image down.
gen_hex32() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    od -An -tx1 -N32 /dev/urandom | tr -d ' \n'
  fi
}

# buzz-admin generate-key produces a valid secp256k1 keypair. It needs no DB
# or Redis, so it is safe to call before the rest of the stack is reachable.
gen_relay_key() {
  local key=""
  if command -v buzz-admin >/dev/null 2>&1; then
    key="$(buzz-admin generate-key 2>/dev/null | awk '/Secret key/ {print $3}' || true)"
  fi
  if [[ "${key}" =~ ^[0-9a-fA-F]{64}$ ]]; then
    printf '%s' "${key}"
  else
    gen_hex32
  fi
}

# ── bech32 npub → hex ───────────────────────────────────────────────────────
# The Buzz desktop app shows your identity as npub1..., but RELAY_OWNER_PUBKEY
# must be 64-char hex. Rather than making the operator find a converter, decode
# it here. Checksum is dropped rather than verified: a malformed npub simply
# yields a pubkey that never matches, which fails closed.
npub2hex() {
  local input="${1,,}" charset="qpzry9x8gf2tvdw0s3jn54khce6mua7l"
  [[ "${input}" == npub1* ]] || return 1
  local body="${input:5}"
  (( ${#body} > 6 )) || return 1
  local data="${body:0:$(( ${#body} - 6 ))}"
  local acc=0 bits=0 out="" i c v byte
  for (( i=0; i<${#data}; i++ )); do
    c="${data:i:1}"
    v="${charset%%"${c}"*}"
    [[ "${v}" == "${charset}" ]] && return 1
    v=${#v}
    acc=$(( (acc << 5) | v ))
    bits=$(( bits + 5 ))
    while (( bits >= 8 )); do
      bits=$(( bits - 8 ))
      byte=$(( (acc >> bits) & 0xff ))
      printf -v c '%02x' "${byte}"
      out+="${c}"
    done
  done
  (( ${#out} == 64 )) || return 1
  printf '%s' "${out}"
}

# ── First boot: write the operator-editable config ──────────────────────────
mkdir -p "${CONFIG_DIR}"

if [[ ! -f "${CONFIG_FILE}" ]]; then
  log "first boot — generating ${CONFIG_FILE}"
  _relay_key="$(gen_relay_key)"
  _hmac="$(gen_hex32)"

  cat > "${CONFIG_FILE}" <<EOF
# =============================================================================
# Buzz relay — configurazione AxeHero / umbrelOS
# =============================================================================
# Modifica questo file e poi riavvia l'app da umbrelOS.
# Percorso sull'host: ~/umbrel/app-data/axehero-buzz/config/buzz.env
# =============================================================================

# -----------------------------------------------------------------------------
# 1. HOSTNAME PUBBLICO  ⚠️  IMPOSTALO PRIMA DI INIZIARE A USARE BUZZ
# -----------------------------------------------------------------------------
# Il relay usa l'host di RELAY_URL come identita' della community. Cambiarlo
# DOPO aver creato canali e messaggi crea una community nuova e vuota: i dati
# vecchi restano nel database ma non sono piu' raggiungibili.
#
# LAN (default):              umbrel.local:3399     + BUZZ_PUBLIC_TLS=false
# Reverse proxy / HTTPS:      buzz.miodominio.it    + BUZZ_PUBLIC_TLS=true
BUZZ_PUBLIC_HOST=umbrel.local:3399
BUZZ_PUBLIC_TLS=false

# -----------------------------------------------------------------------------
# 2. PROPRIETARIO DEL RELAY (modalita' chiusa)
# -----------------------------------------------------------------------------
# Finche' e' vuoto il relay parte in modalita' APERTA: chiunque raggiunga
# l'URL puo' registrarsi. Va bene solo in LAN, per il primo accesso.
#
# Flusso: avvia l'app -> apri Buzz desktop -> crea la tua identita' ->
# copia il tuo npub -> incollalo qui -> riavvia l'app.
# Accetta sia npub1... sia i 64 caratteri esadecimali.
RELAY_OWNER_PUBKEY=

# -----------------------------------------------------------------------------
# 3. PAIRING MOBILE (opzionale)
# -----------------------------------------------------------------------------
# URL WebSocket del servizio pairing separato. Impostalo quando esponi il
# servizio pair sulla porta host 5001 tramite un reverse proxy, per esempio:
# BUZZ_PAIRING_RELAY_URL=wss://pair.buzz.miodominio.it
BUZZ_PAIRING_RELAY_URL=

# -----------------------------------------------------------------------------
# 4. SEGRETI — generati automaticamente, NON modificarli
# -----------------------------------------------------------------------------
# La chiave del relay firma le liste di membri (kind:13534) e i post creati via
# REST. Se la perdi o la cambi, quelle firme non sono piu' verificabili.
# Includi questo file nei tuoi backup.
BUZZ_RELAY_PRIVATE_KEY=${_relay_key}
BUZZ_GIT_HOOK_HMAC_SECRET=${_hmac}

# -----------------------------------------------------------------------------
# 5. OPZIONALI
# -----------------------------------------------------------------------------
# Espone il browser dei repository git sulla web UI.
BUZZ_SERVE_GIT_WEB_GUI=false
# Verbosita' dei log: error | warn | info | debug
BUZZ_LOG_LEVEL=info
EOF

  chmod 600 "${CONFIG_FILE}" 2>/dev/null || true
  unset _relay_key _hmac
  log "config creata — vedi il README dell'app per i passi successivi"
fi

# ── Load operator config ────────────────────────────────────────────────────
set -a
# shellcheck disable=SC1090
. "${CONFIG_FILE}"
set +a

# ── Derive URL-shaped settings from one source of truth ─────────────────────
BUZZ_PUBLIC_HOST="${BUZZ_PUBLIC_HOST:-umbrel.local:3399}"
BUZZ_PUBLIC_TLS="${BUZZ_PUBLIC_TLS:-false}"

if [[ "${BUZZ_PUBLIC_TLS,,}" == "true" ]]; then
  _ws="wss"; _http="https"
else
  _ws="ws"; _http="http"
fi

export RELAY_URL="${_ws}://${BUZZ_PUBLIC_HOST}"
export BUZZ_MEDIA_BASE_URL="${_http}://${BUZZ_PUBLIC_HOST}/media"
export BUZZ_MEDIA_SERVER_DOMAIN="${BUZZ_PUBLIC_HOST%%:*}"
export BUZZ_CORS_ORIGINS="${_http}://${BUZZ_PUBLIC_HOST}"
export RUST_LOG="buzz_relay=${BUZZ_LOG_LEVEL:-info},buzz_db=${BUZZ_LOG_LEVEL:-info},buzz_auth=${BUZZ_LOG_LEVEL:-info},buzz_pubsub=${BUZZ_LOG_LEVEL:-info},tower_http=warn"

# Do not pass an empty pairing URL: the relay must omit pairing metadata when
# mobile pairing has not been configured.
if [[ -z "${BUZZ_PAIRING_RELAY_URL:-}" ]]; then
  unset BUZZ_PAIRING_RELAY_URL
fi

# ── Owner pubkey → closed relay mode ────────────────────────────────────────
_owner="${RELAY_OWNER_PUBKEY:-}"
_owner="${_owner//[[:space:]]/}"

if [[ -n "${_owner}" ]]; then
  if [[ "${_owner}" =~ ^[0-9a-fA-F]{64}$ ]]; then
    _owner="${_owner,,}"
  elif _decoded="$(npub2hex "${_owner}")"; then
    log "RELAY_OWNER_PUBKEY convertito da npub a hex"
    _owner="${_decoded}"
  else
    banner <<'EOF'
ERRORE DI CONFIGURAZIONE

RELAY_OWNER_PUBKEY non e' valido. Deve essere un npub1...
oppure 64 caratteri esadecimali.

Correggi config/buzz.env e riavvia l'app.
EOF
    exit 1
  fi

  export RELAY_OWNER_PUBKEY="${_owner}"
  export BUZZ_REQUIRE_AUTH_TOKEN=true
  export BUZZ_REQUIRE_RELAY_MEMBERSHIP=true
  export BUZZ_ALLOW_NIP_OA_AUTH=true
  log "relay CHIUSO — owner ${_owner:0:16}…"
else
  unset RELAY_OWNER_PUBKEY
  export BUZZ_REQUIRE_AUTH_TOKEN=false
  export BUZZ_REQUIRE_RELAY_MEMBERSHIP=false
  banner <<EOF

!!  RELAY IN MODALITA' APERTA  !!

Chiunque raggiunga ${RELAY_URL} puo' registrarsi
e creare canali. Non esporlo su internet cosi'.

Per chiuderlo:
  1. Apri l'app Buzz desktop e crea la tua identita'
  2. Copia il tuo npub
  3. Incollalo in RELAY_OWNER_PUBKEY dentro
     ~/umbrel/app-data/axehero-buzz/config/buzz.env
  4. Riavvia l'app Buzz da umbrelOS

EOF
fi

if [[ "${BUZZ_PUBLIC_TLS,,}" != "true" && "${BUZZ_PUBLIC_HOST}" != *umbrel.local* ]]; then
  log "attenzione: BUZZ_PUBLIC_HOST=${BUZZ_PUBLIC_HOST} ma BUZZ_PUBLIC_TLS=false"
fi

log "RELAY_URL=${RELAY_URL}"
log "avvio buzz-relay…"

exec /usr/local/bin/buzz-relay "$@"
