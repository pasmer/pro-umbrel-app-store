#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${BUZZ_AGENTS_CONFIG_DIR:-/config}"
CONFIG_FILE="${CONFIG_DIR}/agents.env"
DATA_DIR="${BUZZ_AGENTS_DATA_DIR:-/data}"
SOURCE_DIR="${DATA_DIR}/buzz-source"
BIN_DIR="${DATA_DIR}/bin"
WORK_DIR="${DATA_DIR}/workspaces"
BUZZ_SOURCE_REF="${BUZZ_SOURCE_REF:-main}"

log() { printf '[buzz-agents] %s\n' "$*" >&2; }

mkdir -p "${CONFIG_DIR}" "${BIN_DIR}" "${WORK_DIR}" \
  "${WORK_DIR}/fizz" "${WORK_DIR}/honey" "${WORK_DIR}/pollen"

if [[ ! -f "${CONFIG_FILE}" ]]; then
  cat >"${CONFIG_FILE}" <<'EOF'
# Buzz Agents — configurazione locale dell'istanza Umbrel
# Non pubblicare questo file: contiene chiavi private e una API key.
#
# Per preservare gli agenti già presenti sul Mac, usa le rispettive chiavi
# private Nostr. Non usare BUZZ_RELAY_PRIVATE_KEY: quella appartiene al relay.

BUZZ_RELAY_URL=wss://team.smartinstitute.org
# Necessario se il relay richiede il token oltre all'autenticazione NIP-42.
BUZZ_API_TOKEN=
OPENROUTER_API_KEY=

# Usa un tag o un commit upstream per build riproducibili. main segue sempre
# l'ultima versione disponibile e può richiedere una ricompilazione.
BUZZ_SOURCE_REF=main

# Fizz
FIZZ_PRIVATE_KEY=
FIZZ_MODEL=inclusionai/ling-3.0-flash-sante:free
FIZZ_SYSTEM_PROMPT=

# Honey
HONEY_PRIVATE_KEY=
HONEY_MODEL=z-ai/glm-5.3-flash
HONEY_SYSTEM_PROMPT=

# Pollen
POLLEN_PRIVATE_KEY=
POLLEN_MODEL=z-ai/glm-5.3-flash
POLLEN_SYSTEM_PROMPT=
EOF
  chmod 600 "${CONFIG_FILE}" 2>/dev/null || true
  log "creato ${CONFIG_FILE}; inserisci le tre chiavi private e OPENROUTER_API_KEY, poi riavvia l'app"
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "${CONFIG_FILE}"
set +a

BUZZ_RELAY_URL="${BUZZ_RELAY_URL:-wss://team.smartinstitute.org}"
OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"
BUZZ_API_TOKEN="${BUZZ_API_TOKEN:-}"
BUZZ_SOURCE_REF="${BUZZ_SOURCE_REF:-main}"

if [[ -z "${OPENROUTER_API_KEY}" ]]; then
  log "OPENROUTER_API_KEY non impostata in ${CONFIG_FILE}"
  exit 1
fi

for name in buzz-acp buzz-agent buzz-cli buzz-dev-mcp; do
  if [[ ! -x "${BIN_DIR}/${name}" ]]; then
    NEED_BUILD=1
    break
  fi
done

if [[ "${NEED_BUILD:-0}" == 1 ]]; then
  log "preparo i binari Buzz per ARM64 (prima installazione; può richiedere tempo)"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates git pkg-config libssl-dev
  rm -rf /var/lib/apt/lists/*

  if [[ ! -d "${SOURCE_DIR}/.git" ]]; then
    rm -rf "${SOURCE_DIR}"
    git clone --filter=blob:none https://github.com/block/buzz.git "${SOURCE_DIR}"
  fi
  git -C "${SOURCE_DIR}" fetch --depth=1 origin "${BUZZ_SOURCE_REF}" || true
  git -C "${SOURCE_DIR}" checkout --force "${BUZZ_SOURCE_REF}"
  git -C "${SOURCE_DIR}" clean -fdx

  cargo build --release --locked \
    --manifest-path "${SOURCE_DIR}/Cargo.toml" \
    -p buzz-acp -p buzz-agent -p buzz-cli -p buzz-dev-mcp

  install -m 0755 "${SOURCE_DIR}/target/release/buzz-acp" "${BIN_DIR}/buzz-acp"
  install -m 0755 "${SOURCE_DIR}/target/release/buzz-agent" "${BIN_DIR}/buzz-agent"
  install -m 0755 "${SOURCE_DIR}/target/release/buzz" "${BIN_DIR}/buzz-cli"
  install -m 0755 "${SOURCE_DIR}/target/release/buzz-dev-mcp" "${BIN_DIR}/buzz-dev-mcp"
fi

if [[ -z "${FIZZ_PRIVATE_KEY:-}" || -z "${HONEY_PRIVATE_KEY:-}" || -z "${POLLEN_PRIVATE_KEY:-}" ]]; then
  log "manca almeno una chiave privata: FIZZ_PRIVATE_KEY, HONEY_PRIVATE_KEY o POLLEN_PRIVATE_KEY"
  exit 1
fi

run_agent() {
  local label="$1" key="$2" model="$3" prompt="$4" workdir="$5"
  log "avvio ${label} con modello ${model}"
  cd "${workdir}"
  local -a env_args=(
    "BUZZ_PRIVATE_KEY=${key}"
    "BUZZ_RELAY_URL=${BUZZ_RELAY_URL}"
    "BUZZ_AGENT_PROVIDER=openrouter"
    "OPENROUTER_API_KEY=${OPENROUTER_API_KEY}"
    "OPENROUTER_MODEL=${model}"
    "OPENROUTER_BASE_URL=https://openrouter.ai/api/v1"
    "BUZZ_ACP_AGENT_COMMAND=${BIN_DIR}/buzz-agent"
    "BUZZ_ACP_AGENT_ARGS="
    "BUZZ_ACP_MCP_COMMAND=${BIN_DIR}/buzz-dev-mcp"
    "BUZZ_ACP_AGENTS=1"
    "BUZZ_ACP_RESPOND_TO=owner-only"
    "BUZZ_AGENT_REQUIRE_REPLY=1"
  )
  if [[ -n "${BUZZ_API_TOKEN}" ]]; then
    env_args+=("BUZZ_API_TOKEN=${BUZZ_API_TOKEN}")
  fi
  if [[ -n "${prompt}" ]]; then
    env_args+=("BUZZ_AGENT_SYSTEM_PROMPT=${prompt}")
  fi
  env "${env_args[@]}" "${BIN_DIR}/buzz-acp" &
}

run_agent "Fizz" "${FIZZ_PRIVATE_KEY}" "${FIZZ_MODEL}" \
  "${FIZZ_SYSTEM_PROMPT:-}" "${WORK_DIR}/fizz"
run_agent "Honey" "${HONEY_PRIVATE_KEY}" "${HONEY_MODEL}" \
  "${HONEY_SYSTEM_PROMPT:-}" "${WORK_DIR}/honey"
run_agent "Pollen" "${POLLEN_PRIVATE_KEY}" "${POLLEN_MODEL}" \
  "${POLLEN_SYSTEM_PROMPT:-}" "${WORK_DIR}/pollen"

trap 'kill 0' TERM INT
wait -n
status=$?
log "un runner è terminato con codice ${status}; riavvio lo stack tramite restart policy"
exit "${status}"
