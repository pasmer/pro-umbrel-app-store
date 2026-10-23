#!/bin/bash
# ---------------------------------------------------------------------------
# fix-svm.sh
# Ripristina l'app axehero-rating-svm-web sull'UmbrelOS.
#
# Uso:  bash ~/Documents/App/pro-umbrel-app-store/fix-svm.sh
#
# Cosa fa (in ordine, tutto loggato in svm-fix.txt):
#   1. verifica su Docker Hub quale nome immagine esiste davvero
#      (pasmer/rating-svm-web vs pasmer/svm-rating)
#   2. rende disponibile l'immagine corretta (pull o retag locale)
#   3. avvia l'app con docker compose (progetto axehero-rating-svm-web)
#   4. riavvia nginx-proxy-manager_docker-host_1 (in crash-loop)
#   5. verifica la porta 8000 e raccoglie la config NPM per svm.merella.it
#
# Non cancella immagini, non tocca app-data, non modifica altre app.
# ---------------------------------------------------------------------------
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$DIR/svm-fix.txt"
ENVF="$DIR/.env"

[ -f "$ENVF" ] || { echo "ERRORE: non trovo $ENVF"; exit 1; }
# shellcheck disable=SC1090
set -a; . "$ENVF"; set +a

HOST="${SSH_HOST:-}"; SUSER="${SSH_USER:-}"; SPORT="${SSH_PORT:-22}"; PW="${SSH_PASSWORD:-}"
[ -n "$HOST" ] && [ -n "$SUSER" ] && [ -n "$PW" ] || { echo "ERRORE: .env incompleto"; exit 1; }
command -v expect >/dev/null 2>&1 || { echo "ERRORE: 'expect' non disponibile."; exit 1; }

REMOTE_SCRIPT=$(cat <<'REOF'
#!/bin/bash
APP=axehero-rating-svm-web
CNT=rating-svm-web
UMB="$HOME/umbrel"; [ -d "$UMB" ] || UMB=/home/umbrel/umbrel
CDIR="$UMB/app-data/$APP"

if docker ps >/dev/null 2>&1; then NEEDSUDO=0; else NEEDSUDO=1; fi
dk(){ if [ "$NEEDSUDO" = "0" ]; then docker "$@"; else printf '%s\n' "$SUDOPW" | sudo -S -p '' docker "$@"; fi; }
hdr(){ echo; echo "########## $* ##########"; }

echo "=== FIX axehero-rating-svm-web  ($(date)) ==="

# ---------------------------------------------------------------- 1. Hub check
hdr "1. VERIFICA NOMI SU DOCKER HUB"
hub_has(){ # $1 = repo, $2 = tag
  local tok
  tok=$(curl -sS -m 20 "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$1:pull" \
        | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
  [ -n "$tok" ] || return 1
  curl -sS -m 20 -o /dev/null -w '%{http_code}' \
       -H "Authorization: Bearer $tok" \
       -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json" \
       "https://registry-1.docker.io/v2/$1/manifests/$2" | grep -q '^200$'
}
HUB_A=NO; HUB_B=NO
hub_has pasmer/rating-svm-web 1.0.1 && HUB_A=SI
hub_has pasmer/svm-rating     1.0.1 && HUB_B=SI
echo "pasmer/rating-svm-web:1.0.1 su Docker Hub : $HUB_A"
echo "pasmer/svm-rating:1.0.1     su Docker Hub : $HUB_B"
echo "-- tag disponibili sotto pasmer/svm-rating --"
curl -sS -m 20 "https://hub.docker.com/v2/repositories/pasmer/svm-rating/tags?page_size=20" | tr ',' '\n' | grep '"name"' | head -20
echo "-- tag disponibili sotto pasmer/rating-svm-web --"
curl -sS -m 20 "https://hub.docker.com/v2/repositories/pasmer/rating-svm-web/tags?page_size=20" | tr ',' '\n' | grep '"name"' | head -20

# ------------------------------------------------- 2. immagine corretta locale
hdr "2. PREPARAZIONE IMMAGINE"
TARGET="pasmer/rating-svm-web:1.0.1"   # nome atteso dal compose installato
if [ "$HUB_A" = "SI" ]; then
  echo "-> il nome nel compose esiste su Hub: eseguo pull"
  dk pull "$TARGET" 2>&1 | tail -5
elif dk image inspect pasmer/svm-rating:1.0.1 >/dev/null 2>&1; then
  echo "-> uso l'immagine locale pasmer/svm-rating:1.0.1 e la ritaggo come $TARGET"
  dk tag pasmer/svm-rating:1.0.1 "$TARGET" 2>&1
elif [ "$HUB_B" = "SI" ]; then
  echo "-> scarico pasmer/svm-rating:1.0.1 e la ritaggo come $TARGET"
  dk pull pasmer/svm-rating:1.0.1 2>&1 | tail -5
  dk tag pasmer/svm-rating:1.0.1 "$TARGET" 2>&1
else
  echo "!! NESSUNA IMMAGINE UTILIZZABILE TROVATA — mi fermo qui."
  echo "########## FINE FIX ##########"; exit 1
fi
echo "-- immagini 'rating|svm' ora presenti --"
dk images 2>&1 | grep -iE 'rating|svm'

# ------------------------------------------------------------- 3. avvio dell'app
hdr "3. AVVIO APP"
echo "-- compose usato: $CDIR/docker-compose.yml"
dk network inspect umbrel_main_network >/dev/null 2>&1 || echo "ATTENZIONE: rete umbrel_main_network assente"
if [ "$NEEDSUDO" = "0" ]; then
  (cd "$CDIR" && docker compose -p "$APP" up -d 2>&1 | tail -20)
else
  printf '%s\n' "$SUDOPW" | sudo -S -p '' bash -c "cd '$CDIR' && docker compose -p '$APP' up -d" 2>&1 | tail -20
fi
sleep 6
echo "-- stato --"
dk ps -a --format '{{.Names}} | {{.Status}} | {{.Ports}} | {{.Image}}' 2>&1 | grep -iE 'rating|svm' || echo "container non trovato"
echo "-- log (60 righe) --"
dk logs --tail 60 "$CNT" 2>&1

# ------------------------------------------------------- 4. NPM / docker-host
hdr "4. NGINX PROXY MANAGER"
echo "-- log docker-host (40 righe) --"
dk logs --tail 40 nginx-proxy-manager_docker-host_1 2>&1
echo "-- riavvio docker-host --"
dk restart nginx-proxy-manager_docker-host_1 2>&1
sleep 8
dk ps -a --format '{{.Names}} | {{.Status}}' 2>&1 | grep -i nginx-proxy-manager
echo "-- proxy host configurati in NPM --"
dk exec nginx-proxy-manager_web_1 sh -c "ls /data/nginx/proxy_host/ 2>/dev/null && grep -l -r 'svm' /data/nginx/proxy_host/ 2>/dev/null | head -5" 2>&1 | head -30
echo "-- regola NPM che contiene 'svm' --"
dk exec nginx-proxy-manager_web_1 sh -c "grep -r -A6 -B2 'svm\.merella\.it' /data/nginx/proxy_host/ 2>/dev/null | head -40" 2>&1 | head -40

# --------------------------------------------------------------- 5. verifiche
hdr "5. VERIFICHE"
echo "-- porte in ascolto --"
(ss -tlnp 2>/dev/null || printf '%s\n' "$SUDOPW" | sudo -S -p '' ss -tlnp 2>/dev/null) | grep -E ':(8000|40080|40443) '
echo "-- curl 127.0.0.1:8000 --"
curl -sS -o /dev/null -w 'http_code=%{http_code} time=%{time_total}s\n' -m 10 http://127.0.0.1:8000/ 2>&1
echo "-- curl 192.168.1.112:8000 --"
curl -sS -o /dev/null -w 'http_code=%{http_code} time=%{time_total}s\n' -m 10 http://192.168.1.112:8000/ 2>&1
echo "-- DNS svm.merella.it --"
(getent hosts svm.merella.it || nslookup svm.merella.it 2>&1 | tail -6) 2>&1
echo "-- curl https://svm.merella.it --"
curl -sS -o /dev/null -w 'http_code=%{http_code} time=%{time_total}s\n' -m 20 https://svm.merella.it/ 2>&1

echo
echo "########## FINE FIX ##########"
REOF
)

B64=$(printf '%s' "$REMOTE_SCRIPT" | base64 | tr -d '\n')
RCMD="export SUDOPW='$PW'; echo $B64 | base64 -d > /tmp/svm_fix.sh; bash /tmp/svm_fix.sh; rm -f /tmp/svm_fix.sh"

echo "Connessione a $SUSER@$HOST:$SPORT ..."
echo "(output in $OUT)"

expect -c "
set timeout 600
log_file -noappend {$OUT}
spawn ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=15 -p $SPORT $SUSER@$HOST {$RCMD}
expect {
  -re {[Pp]assword:} { send -- \"$PW\r\"; exp_continue }
  -re {\(yes/no} { send -- \"yes\r\"; exp_continue }
  timeout { puts \"\n*** TIMEOUT ***\"; exit 2 }
  eof
}
"
RC=$?

if [ -f "$OUT" ]; then
  LC_ALL=C sed -i '' "s/$(printf '%s' "$PW" | sed 's/[\/&]/\\\\&/g')/***PASSWORD***/g" "$OUT" 2>/dev/null
  echo; echo "Fatto (exit $RC). File salvato: $OUT"
else
  echo "ERRORE: nessun output prodotto (exit $RC)."
fi
