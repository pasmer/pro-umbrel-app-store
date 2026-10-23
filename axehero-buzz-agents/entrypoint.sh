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

write_default_config() {
  cat >"${CONFIG_FILE}" <<'EOF'
# Buzz Agents — configurazione locale dell'istanza Umbrel
# Non pubblicare questo file: contiene chiavi private e una API key.
#
# Per preservare gli agenti già presenti sul Mac, usa le rispettive chiavi
# private Nostr. Non usare BUZZ_RELAY_PRIVATE_KEY: quella appartiene al relay.

BUZZ_RELAY_URL=wss://team.smartinstitute.org
# Necessario se il relay richiede il token oltre all'autenticazione NIP-42.
BUZZ_API_TOKEN=
OMNIROUTE_API_KEY=
OMNIROUTE_BASE_URL=http://192.168.1.112:20128/v1
OMNIROUTE_API=chat
OMNIROUTE_MODEL=auto

# Usa un tag o un commit upstream per build riproducibili. main segue sempre
# l'ultima versione disponibile e può richiedere una ricompilazione.
BUZZ_SOURCE_REF=main

# Lascia vuota una chiave per non avviare quell'agente.
FIZZ_PRIVATE_KEY=
FIZZ_MODEL=auto
FIZZ_SYSTEM_PROMPT=
# Pubkey esadecimale del proprietario del relay per il filtro owner-only.
FIZZ_AGENT_OWNER=

HONEY_PRIVATE_KEY=
HONEY_MODEL=auto
HONEY_SYSTEM_PROMPT=

POLLEN_PRIVATE_KEY=
POLLEN_MODEL=auto
POLLEN_SYSTEM_PROMPT=
EOF
}

wait_for_configuration() {
  log "$1"
  log "modifica ${CONFIG_FILE} e riavvia l'app quando la configurazione è pronta"
  while sleep 300; do
    log "configurazione ancora incompleta; container in attesa a basso consumo"
  done
}

if [[ ! -f "${CONFIG_FILE}" ]]; then
  write_default_config
  chmod 600 "${CONFIG_FILE}" 2>/dev/null || true
  wait_for_configuration "creato ${CONFIG_FILE}"
fi

set -a
# shellcheck disable=SC1090
. "${CONFIG_FILE}"
set +a

BUZZ_RELAY_URL="${BUZZ_RELAY_URL:-wss://team.smartinstitute.org}"
OMNIROUTE_API_KEY="${OMNIROUTE_API_KEY:-}"
OMNIROUTE_BASE_URL="${OMNIROUTE_BASE_URL:-http://192.168.1.112:20128/v1}"
OMNIROUTE_API="${OMNIROUTE_API:-chat}"
OMNIROUTE_MODEL="${OMNIROUTE_MODEL:-auto}"
BUZZ_API_TOKEN="${BUZZ_API_TOKEN:-}"
BUZZ_SOURCE_REF="${BUZZ_SOURCE_REF:-main}"

if [[ -z "${OMNIROUTE_API_KEY}" ]]; then
  wait_for_configuration "OMNIROUTE_API_KEY non impostata in ${CONFIG_FILE}"
fi

for name in buzz-acp buzz-agent buzz-cli buzz-dev-mcp; do
  if [[ ! -x "${BIN_DIR}/${name}" ]]; then
    NEED_BUILD=1
    break
  fi
done

build_binaries() {
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
}

if [[ "${NEED_BUILD:-0}" == 1 ]]; then
  # Un errore di rete o di compilazione non deve trasformarsi in un restart loop.
  # Ritenta con una pausa lunga lasciando il container vivo e diagnosticabile.
  until build_binaries; do
    log "preparazione dei binari fallita; nuovo tentativo tra 300 secondi"
    sleep 300
  done
fi

if [[ -z "${FIZZ_PRIVATE_KEY:-}" && -z "${HONEY_PRIVATE_KEY:-}" && -z "${POLLEN_PRIVATE_KEY:-}" ]]; then
  wait_for_configuration "nessun agente configurato: imposta almeno una chiave privata"
fi

run_agent() {
  local label="$1" key="$2" model="$3" prompt="$4" workdir="$5"
  local restart_delay=5

  while true; do
    log "avvio ${label} con modello ${model} tramite OmniRoute"
    cd "${workdir}"
    local -a env_args=(
      "BUZZ_PRIVATE_KEY=${key}"
      "BUZZ_RELAY_URL=${BUZZ_RELAY_URL}"
      "BUZZ_AGENT_PROVIDER=openai"
      "OPENAI_COMPAT_API_KEY=${OMNIROUTE_API_KEY}"
      "OPENAI_COMPAT_MODEL=${model}"
      "OPENAI_COMPAT_BASE_URL=${OMNIROUTE_BASE_URL}"
      "OPENAI_COMPAT_API=${OMNIROUTE_API}"
      "BUZZ_ACP_AGENT_COMMAND=${BIN_DIR}/buzz-agent"
      "BUZZ_ACP_AGENT_ARGS="
      "BUZZ_ACP_MCP_COMMAND=${BIN_DIR}/buzz-dev-mcp"
      "BUZZ_ACP_AGENTS=1"
      "BUZZ_ACP_RESPOND_TO=owner-only"
      "BUZZ_AGENT_REQUIRE_REPLY=1"
    )
    if [[ "${label}" == "Fizz" && -n "${FIZZ_AGENT_OWNER:-}" ]]; then
      env_args+=("BUZZ_ACP_AGENT_OWNER=${FIZZ_AGENT_OWNER}")
    fi
    if [[ -n "${BUZZ_API_TOKEN}" ]]; then
      env_args+=("BUZZ_API_TOKEN=${BUZZ_API_TOKEN}")
    fi
    if [[ -n "${prompt}" ]]; then
      env_args+=("BUZZ_AGENT_SYSTEM_PROMPT=${prompt}")
    fi

    local started_at status elapsed
    started_at="$(date +%s)"
    set +e
    env "${env_args[@]}" "${BIN_DIR}/buzz-acp"
    status=$?
    set -e
    elapsed=$(( $(date +%s) - started_at ))

    log "${label} terminato con codice ${status} dopo ${elapsed}s"
    if (( elapsed >= 60 )); then
      restart_delay=5
    else
      restart_delay=$(( restart_delay * 2 ))
      (( restart_delay > 300 )) && restart_delay=300
    fi
    log "riavvio controllato di ${label} tra ${restart_delay}s"
    sleep "${restart_delay}"
  done
}

AGENT_PIDS=()
if [[ -n "${FIZZ_PRIVATE_KEY:-}" ]]; then
  run_agent "Fizz" "${FIZZ_PRIVATE_KEY}" "${FIZZ_MODEL:-${OMNIROUTE_MODEL}}" \
    "${FIZZ_SYSTEM_PROMPT:-}" "${WORK_DIR}/fizz" & AGENT_PIDS+=("$!")
else
  log "Fizz disabilitato: FIZZ_PRIVATE_KEY non impostata"
fi
if [[ -n "${HONEY_PRIVATE_KEY:-}" ]]; then
  run_agent "Honey" "${HONEY_PRIVATE_KEY}" "${HONEY_MODEL:-${OMNIROUTE_MODEL}}" \
    "${HONEY_SYSTEM_PROMPT:-}" "${WORK_DIR}/honey" & AGENT_PIDS+=("$!")
else
  log "Honey disabilitato: HONEY_PRIVATE_KEY non impostata"
fi
if [[ -n "${POLLEN_PRIVATE_KEY:-}" ]]; then
  run_agent "Pollen" "${POLLEN_PRIVATE_KEY}" "${POLLEN_MODEL:-${OMNIROUTE_MODEL}}" \
    "${POLLEN_SYSTEM_PROMPT:-}" "${WORK_DIR}/pollen" & AGENT_PIDS+=("$!")
else
  log "Pollen disabilitato: POLLEN_PRIVATE_KEY non impostata"
fi

cleanup() {
  log "arresto dei runner"
  trap - TERM INT
  if ((${#AGENT_PIDS[@]} > 0)); then
    kill "${AGENT_PIDS[@]}" 2>/dev/null || true
    wait "${AGENT_PIDS[@]}" 2>/dev/null || true
  fi
  exit 0
}
trap cleanup TERM INT

# Il supervisore resta vivo senza polling aggressivo. I runner gestiscono da soli
# i loro riavvii con backoff; il container non deve entrare in restart loop.
while true; do
  sleep 3600
done
