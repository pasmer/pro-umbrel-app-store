#!/bin/bash
# ---------------------------------------------------------------------------
# diagnose-svm.sh
# Raccoglie una diagnostica completa dall'UmbrelOS per l'app
# axehero-rating-svm-web (container: rating-svm-web).
#
# Uso:  bash ~/Documents/App/pro-umbrel-app-store/diagnose-svm.sh
#
# Legge le credenziali SSH da .env nella stessa cartella e scrive il
# risultato in svm-diagnostics.txt (password oscurata).
# NON modifica nulla sull'Umbrel: solo lettura.
# ---------------------------------------------------------------------------
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$DIR/svm-diagnostics.txt"
ENVF="$DIR/.env"

[ -f "$ENVF" ] || { echo "ERRORE: non trovo $ENVF"; exit 1; }
# shellcheck disable=SC1090
set -a; . "$ENVF"; set +a

HOST="${SSH_HOST:-}"; SUSER="${SSH_USER:-}"; SPORT="${SSH_PORT:-22}"; PW="${SSH_PASSWORD:-}"
[ -n "$HOST" ] && [ -n "$SUSER" ] && [ -n "$PW" ] || { echo "ERRORE: .env incompleto"; exit 1; }

command -v expect >/dev/null 2>&1 || { echo "ERRORE: 'expect' non disponibile."; exit 1; }

# --------------------------- script remoto ---------------------------------
REMOTE_SCRIPT=$(cat <<'REOF'
#!/bin/bash
APP=axehero-rating-svm-web
CNT=rating-svm-web
UMB="$HOME/umbrel"; [ -d "$UMB" ] || UMB=/home/umbrel/umbrel

if docker ps >/dev/null 2>&1; then NEEDSUDO=0; else NEEDSUDO=1; fi
dk(){ if [ "$NEEDSUDO" = "0" ]; then docker "$@"; else printf '%s\n' "$SUDOPW" | sudo -S -p '' docker "$@"; fi; }
sudocmd(){ printf '%s\n' "$SUDOPW" | sudo -S -p '' "$@"; }
hdr(){ echo; echo "########## $* ##########"; }

echo "=== DIAGNOSTICA axehero-rating-svm-web ==="
echo "docker richiede sudo: $NEEDSUDO   UMBREL_DIR=$UMB"

hdr "DATA / UPTIME";        date; uptime
hdr "SISTEMA";              uname -a; head -3 /etc/os-release 2>/dev/null
hdr "VERSIONE UMBREL";      cat "$UMB/info.json" 2>/dev/null || cat /etc/umbrel-release 2>/dev/null
hdr "DISCO";                df -h
hdr "INODE";                df -i | head -8
hdr "MEMORIA";              free -h
hdr "TEMPERATURA/THROTTLE"; vcgencmd measure_temp 2>/dev/null; vcgencmd get_throttled 2>/dev/null
hdr "OOM KILLER";           (dmesg -T 2>/dev/null || sudocmd dmesg -T 2>/dev/null) | grep -iE "out of memory|oom-killer|killed process" | tail -20
hdr "DOCKER INFO";          dk version --format '{{.Server.Version}}' 2>&1; dk info 2>/dev/null | grep -iE "storage driver|containers|images|warning" | head -20

hdr "CONTAINER (tutti)";    dk ps -a --format '{{.Names}} | {{.Status}} | {{.Ports}} | {{.Image}}' 2>&1
hdr "INSPECT $CNT";         dk inspect "$CNT" --format 'Status={{.State.Status}} Running={{.State.Running}} ExitCode={{.State.ExitCode}} Error="{{.State.Error}}" OOMKilled={{.State.OOMKilled}} Restarts={{.RestartCount}} StartedAt={{.State.StartedAt}} FinishedAt={{.State.FinishedAt}} Image={{.Config.Image}}' 2>&1
hdr "HEALTH $CNT";          dk inspect "$CNT" --format '{{json .State.Health}}' 2>&1
hdr "LOG $CNT (250 righe)"; dk logs --tail 250 "$CNT" 2>&1
hdr "IMMAGINI rating";      dk images 2>&1 | grep -i rating || echo "NESSUNA IMMAGINE 'rating' PRESENTE"
hdr "RETI DOCKER";          dk network ls 2>&1
hdr "RETE umbrel_main_network"; dk network inspect umbrel_main_network --format '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{"\n"}}{{end}}' 2>&1 | head -40

hdr "APP-DATA $APP";        ls -la "$UMB/app-data/$APP" 2>&1
hdr "COMPOSE INSTALLATO";   cat "$UMB/app-data/$APP/docker-compose.yml" 2>&1
hdr "MANIFEST INSTALLATO";  cat "$UMB/app-data/$APP/umbrel-app.yml" 2>&1
hdr "APP-STORES";           ls -la "$UMB/app-stores" 2>&1
hdr "COMPOSE NELLO STORE";  find "$UMB/app-stores" -maxdepth 4 -path "*$APP*" -name "docker-compose.yml" -print -exec cat {} \; 2>&1

hdr "PORTE IN ASCOLTO";     (ss -tlnp 2>/dev/null || sudocmd ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null) | grep -E ':(8000|80|443|81) ' 2>&1
hdr "CURL 127.0.0.1:8000";  curl -sS -o /dev/null -w 'http_code=%{http_code} time=%{time_total}s\n' -m 8 http://127.0.0.1:8000/ 2>&1
hdr "CURL LAN:8000";        curl -sS -o /dev/null -w 'http_code=%{http_code} time=%{time_total}s\n' -m 8 http://192.168.1.112:8000/ 2>&1
hdr "CURL IP CONTAINER";    IPS=$(dk inspect "$CNT" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' 2>/dev/null); echo "IP=$IPS"; for i in $IPS; do curl -sS -o /dev/null -w "$i -> http_code=%{http_code}\n" -m 8 "http://$i:8000/" 2>&1; done

hdr "CLOUDFLARED";          dk ps -a --format '{{.Names}} | {{.Status}}' 2>&1 | grep -i cloudflared || echo "nessun container cloudflared"
for c in $(dk ps -a --format '{{.Names}}' 2>/dev/null | grep -i cloudflared); do echo "-- log $c --"; dk logs --tail 60 "$c" 2>&1; done
hdr "NGINX PROXY MANAGER";  dk ps -a --format '{{.Names}} | {{.Status}}' 2>&1 | grep -iE 'nginx|proxy' || echo "nessun proxy"

hdr "SERVIZI UMBREL";       systemctl is-active umbrel umbreld 2>&1
hdr "JOURNAL UMBREL";       sudocmd journalctl -u umbrel -u umbreld -n 150 --no-pager 2>&1 | tail -150
hdr "UMBREL APP LIST";      "$UMB/scripts/app" list 2>&1 | head -60
hdr "FINE DIAGNOSTICA"
REOF
)

B64=$(printf '%s' "$REMOTE_SCRIPT" | base64 | tr -d '\n')
RCMD="export SUDOPW='$PW'; echo $B64 | base64 -d > /tmp/svm_diag.sh; bash /tmp/svm_diag.sh; rm -f /tmp/svm_diag.sh"

echo "Connessione a $SUSER@$HOST:$SPORT ..."
echo "(output in $OUT)"

expect -c "
set timeout 420
log_file -noappend {$OUT}
spawn ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=15 -p $SPORT $SUSER@$HOST {$RCMD}
expect {
  -re {[Pp]assword:} { send -- \"$PW\r\"; exp_continue }
  -re {\(yes/no} { send -- \"yes\r\"; exp_continue }
  -re {FINE DIAGNOSTICA} { exp_continue }
  timeout { puts \"\n*** TIMEOUT ***\"; exit 2 }
  eof
}
"
RC=$?

# oscura la password nel file di output
if [ -f "$OUT" ]; then
  LC_ALL=C sed -i '' "s/$(printf '%s' "$PW" | sed 's/[\/&]/\\\\&/g')/***PASSWORD***/g" "$OUT" 2>/dev/null
  echo
  echo "Fatto (exit $RC). File salvato: $OUT"
  echo "Righe: $(wc -l < "$OUT")"
else
  echo "ERRORE: nessun output prodotto (exit $RC)."
fi
