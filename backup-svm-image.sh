#!/bin/bash
# ---------------------------------------------------------------------------
# backup-svm-image.sh
# Mette in sicurezza l'immagine Docker dell'app CreditRating PMI, che al
# momento esiste in UNA SOLA copia: la cache Docker dell'UmbrelOS.
#
# Uso:  bash ~/Documents/App/pro-umbrel-app-store/backup-svm-image.sh
#
# Cosa fa:
#   1. sul Pi: docker save + gzip -> /home/umbrel/svm-image-backup/
#      con sha256, test di integrita' e sidecar JSON di provenienza
#   2. scarica il tarball sul Mac in ~/Documents/App/_docker-image-backups/
#   3. riconfronta lo sha256 fra Pi e Mac
#
# NON cancella nulla, non tocca il container in esecuzione, non richiede token.
# ---------------------------------------------------------------------------
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$DIR/svm-backup.txt"
ENVF="$DIR/.env"
DEST="$HOME/Documents/App/_docker-image-backups"

IMG="pasmer/rating-svm-web:1.0.1"
FNAME="rating-svm-web-1.0.1.tar.gz"
RBK="/home/umbrel/svm-image-backup"

[ -f "$ENVF" ] || { echo "ERRORE: non trovo $ENVF"; exit 1; }
# shellcheck disable=SC1090
set -a; . "$ENVF"; set +a
HOST="${SSH_HOST:-}"; SUSER="${SSH_USER:-}"; SPORT="${SSH_PORT:-22}"; PW="${SSH_PASSWORD:-}"
[ -n "$HOST" ] && [ -n "$SUSER" ] && [ -n "$PW" ] || { echo "ERRORE: .env incompleto"; exit 1; }
command -v expect >/dev/null 2>&1 || { echo "ERRORE: 'expect' non disponibile."; exit 1; }

mkdir -p "$DEST"

# ------------------------------------------------------------ FASE 1: sul Pi
REMOTE_SCRIPT=$(cat <<'REOF'
#!/bin/bash
IMG="pasmer/rating-svm-web:1.0.1"
RBK="/home/umbrel/svm-image-backup"
FNAME="rating-svm-web-1.0.1.tar.gz"

if docker ps >/dev/null 2>&1; then NEEDSUDO=0; else NEEDSUDO=1; fi
dk(){ if [ "$NEEDSUDO" = "0" ]; then docker "$@"; else printf '%s\n' "$SUDOPW" | sudo -S -p '' docker "$@"; fi; }
hdr(){ echo; echo "########## $* ##########"; }

echo "=== BACKUP IMMAGINE $IMG  ($(date)) ==="
mkdir -p "$RBK" || exit 1

hdr "SPAZIO DISPONIBILE"
df -h "$RBK" | tail -1

hdr "PROVENIENZA IMMAGINE"
dk inspect "$IMG" --format 'Id={{.Id}}
Created={{.Created}}
Architecture={{.Architecture}}/{{.Os}}
Size={{.Size}}
RepoTags={{.RepoTags}}
Cmd={{.Config.Cmd}}
Entrypoint={{.Config.Entrypoint}}' 2>&1
dk inspect "$IMG" > "$RBK/rating-svm-web-1.0.1.inspect.json" 2>/dev/null && echo "(inspect salvato in $RBK/rating-svm-web-1.0.1.inspect.json)"

hdr "EXPORT (puo' richiedere 1-3 minuti)"
if [ "$NEEDSUDO" = "0" ]; then
  docker save "$IMG" | gzip -1 > "$RBK/$FNAME"
else
  printf '%s\n' "$SUDOPW" | sudo -S -p '' docker save "$IMG" | gzip -1 > "$RBK/$FNAME"
fi
RC=${PIPESTATUS[0]}
echo "exit docker save = $RC"

hdr "VERIFICA INTEGRITA'"
ls -lh "$RBK/$FNAME"
gzip -t "$RBK/$FNAME" 2>&1 && echo "gzip OK" || echo "!! ARCHIVIO CORROTTO"
echo -n "sha256 = "; sha256sum "$RBK/$FNAME" | cut -d' ' -f1

hdr "CONTENUTO (primi elementi del tar)"
gzip -dc "$RBK/$FNAME" | tar -tf - 2>/dev/null | head -8

echo
echo "########## FINE BACKUP REMOTO ##########"
REOF
)

B64=$(printf '%s' "$REMOTE_SCRIPT" | base64 | tr -d '\n')
RCMD="export SUDOPW='$PW'; echo $B64 | base64 -d > /tmp/svm_bk.sh; bash /tmp/svm_bk.sh; rm -f /tmp/svm_bk.sh"

echo "[1/3] Export dell'immagine sul Pi..."
expect -c "
set timeout 900
log_file -noappend {$OUT}
spawn ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=15 -p $SPORT $SUSER@$HOST {$RCMD}
expect {
  -re {[Pp]assword:} { send -- \"$PW\r\"; exp_continue }
  -re {\(yes/no} { send -- \"yes\r\"; exp_continue }
  timeout { puts \"\n*** TIMEOUT FASE 1 ***\"; exit 2 }
  eof
}
" || { echo "Fase 1 fallita, mi fermo."; exit 1; }

# ------------------------------------------------------- FASE 2: download
echo
echo "[2/3] Download sul Mac in $DEST ..."
expect -c "
set timeout 1800
log_file -append {$OUT}
spawn scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -P $SPORT {$SUSER@$HOST:$RBK/$FNAME} {$DEST/}
expect {
  -re {[Pp]assword:} { send -- \"$PW\r\"; exp_continue }
  -re {\(yes/no} { send -- \"yes\r\"; exp_continue }
  timeout { puts \"\n*** TIMEOUT FASE 2 ***\"; exit 2 }
  eof
}
"
expect -c "
set timeout 300
log_file -append {$OUT}
spawn scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -P $SPORT {$SUSER@$HOST:$RBK/rating-svm-web-1.0.1.inspect.json} {$DEST/}
expect {
  -re {[Pp]assword:} { send -- \"$PW\r\"; exp_continue }
  -re {\(yes/no} { send -- \"yes\r\"; exp_continue }
  timeout { exit 2 }
  eof
}
" >/dev/null 2>&1

# ------------------------------------------------------- FASE 3: confronto
echo
echo "[3/3] Verifica..."
{
  echo
  echo "########## VERIFICA LOCALE (Mac) ##########"
  if [ -f "$DEST/$FNAME" ]; then
    ls -lh "$DEST/$FNAME"
    echo -n "sha256 locale = "; shasum -a 256 "$DEST/$FNAME" | cut -d' ' -f1
    gzip -t "$DEST/$FNAME" 2>&1 && echo "gzip OK" || echo "!! ARCHIVIO LOCALE CORROTTO"
  else
    echo "!! il file non e' arrivato sul Mac"
  fi
  echo "Destinazione: $DEST"
  echo "########## FINE ##########"
} | tee -a "$OUT"

LC_ALL=C sed -i '' "s/$(printf '%s' "$PW" | sed 's/[\/&]/\\\\&/g')/***PASSWORD***/g" "$OUT" 2>/dev/null
echo
echo "Log completo: $OUT"
echo "Confronta a mano i due sha256 nel log: devono coincidere."
