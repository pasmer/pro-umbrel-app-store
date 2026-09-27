# Buzz Agents + OmniRoute su umbrelOS

Guida completa per eseguire Fizz, Honey e Pollen su Umbrel, mantenere gli
agenti online anche quando il Mac è spento e usare OmniRoute come gateway LLM
OpenAI-compatible.

La procedura è pensata per:

- Raspberry Pi / UmbrelOS sulla rete locale;
- relay Buzz \`axehero-buzz\` su Umbrel;
- OmniRoute \`axehero-omniroute\` su Umbrel;
- runner headless \`axehero-buzz-agents\` su Umbrel;
- client Buzz desktop sul Mac e client Buzz mobile su iPhone;
- relay pubblico raggiungibile tramite HTTPS/WebSocket, per esempio
  \`https://team.smartinstitute.org/\` / \`wss://team.smartinstitute.org\`.

> Importante: questa guida contiene solo segnaposto. Non inserire mai nel
> repository password, API key, \`nsec\` o altre chiavi private.

## 1. Architettura finale

\`\`\`text
Buzz Desktop / iPhone
          │
          │ WebSocket sicuro: wss://team.smartinstitute.org
          ▼
Reverse proxy / Nginx Proxy Manager
          │
          ▼
axehero-buzz relay su Umbrel
          │
          ├── membership e canali Buzz
          └── presenza online degli agenti

axehero-buzz-agents
          ├── Fizz ─────┐
          ├── Honey ────┼── relay Buzz
          └── Pollen ───┘
                 │
                 │ OpenAI-compatible HTTP:
                 │ http://192.168.1.112:20128/v1
                 ▼
          OmniRoute
                 │
                 ▼
          provider LLM configurati in OmniRoute
\`\`\`

Il relay gestisce identità Buzz, canali e presenza. OmniRoute gestisce solo
l’inferenza LLM. Le chiavi private degli agenti servono al relay Buzz e non
sono API key di OmniRoute.

## 2. Prerequisiti

Prima di iniziare servono:

- UmbrelOS funzionante, nel nostro esempio raggiungibile a
  \`192.168.1.112\`;
- accesso amministrativo alla dashboard Umbrel;
- dominio pubblico con certificato TLS valido;
- Nginx Proxy Manager o un reverse proxy equivalente;
- repository App Store AxeHero:
  \`https://github.com/pasmer/pro-umbrel-app-store\`;
- client Buzz desktop installato sul Mac;
- accesso al Portachiavi di macOS;
- almeno un provider configurato in OmniRoute.

Mantieni stabile l’indirizzo IP dell’Umbrel con una prenotazione DHCP. Se
l’indirizzo cambia, i container possono continuare a funzionare ma i client e
il runner potrebbero non raggiungere più OmniRoute.

## 3. Installare OmniRoute

Dall’App Store AxeHero installa \`axehero-omniroute\`.

L’app usa la porta \`20128\`. Nel nostro setup la dashboard è raggiungibile a:

\`\`\`text
http://192.168.1.112:20128/home
\`\`\`

L’endpoint OpenAI-compatible da usare per i client è:

\`\`\`text
http://192.168.1.112:20128/v1
\`\`\`

Nella dashboard OmniRoute:

1. configura almeno un provider LLM;
2. abilita o verifica il routing automatico;
3. crea o recupera una API key OmniRoute;
4. verifica che il modello \`auto\` sia disponibile.

Non confondere:

- API key OmniRoute: autorizza le richieste LLM;
- chiave privata Buzz: autentica Fizz/Honey/Pollen sul relay;
- chiave privata del relay: firma il roster dei membri e altri eventi del relay.

Controllo opzionale:

\`\`\`bash
docker ps --filter name=axehero-omniroute
docker logs --tail 100 axehero-omniroute_app_1
\`\`\`

Lo stato del container dovrebbe essere \`Up\` e, quando previsto dalla release,
\`healthy\`.

## 4. Installare e configurare il relay Buzz

Installa \`axehero-buzz\` dall’App Store AxeHero. Il relay espone:

- porta Umbrel \`3399\`: relay Buzz principale;
- porta \`5001\`: servizio pairing mobile.

Al primo avvio il relay può partire in modalità aperta. Questa modalità serve
solo per il bootstrap iniziale e non va lasciata esposta a internet.

### 4.1 Configurare il dominio prima di creare i canali

Il file principale del relay è:

\`\`\`text
~/umbrel/app-data/axehero-buzz/config/buzz.env
\`\`\`

Imposta il dominio definitivo prima di creare canali e messaggi:

\`\`\`env
BUZZ_PUBLIC_HOST=team.smartinstitute.org
BUZZ_PUBLIC_TLS=true
\`\`\`

Il dominio diventa parte dell’identità della community Buzz. Cambiarlo dopo
aver creato canali può far apparire una community nuova e vuota, lasciando i
dati precedenti nel database ma non più raggiungibili dal nuovo host.

### 4.2 Configurare Nginx Proxy Manager

Crea un Proxy Host per il relay principale:

| Campo | Valore |
|---|---|
| Domain Names | \`team.smartinstitute.org\` |
| Scheme | \`http\` |
| Forward Hostname/IP | \`192.168.1.112\` |
| Forward Port | \`3399\` |
| WebSocket Support | attivo |
| SSL | certificato valido per il dominio |
| Force SSL | attivo |

Il client Buzz userà:

\`\`\`text
wss://team.smartinstitute.org
\`\`\`

Non usare \`https://\` come valore del relay nel client: per Buzz il trasporto
è WebSocket, quindi serve \`ws://\` o \`wss://\`.

### 4.3 Configurare il pairing mobile

Se vuoi usare il pairing tramite QR code, crea un secondo Proxy Host. Esempio:

| Campo | Valore |
|---|---|
| Domain Names | \`pair.smartinstitute.org\` |
| Scheme | \`http\` |
| Forward Hostname/IP | \`192.168.1.112\` |
| Forward Port | \`5001\` |
| WebSocket Support | attivo |
| SSL | certificato valido per \`pair.smartinstitute.org\` |
| Force SSL | attivo |

Poi aggiungi al file \`buzz.env\`:

\`\`\`env
BUZZ_PAIRING_RELAY_URL=wss://pair.smartinstitute.org
\`\`\`

Riavvia il relay e verifica che il documento NIP-11 esponga il campo
\`pairing_relay_url\`.

Non aggiungere una pagina di login o una policy interattiva davanti ai WebSocket:
il client Buzz deve poter completare direttamente l’handshake NIP-42.

### 4.4 Collegare Buzz Desktop e definire il proprietario

Collega temporaneamente Buzz Desktop al relay pubblico:

\`\`\`text
wss://team.smartinstitute.org
\`\`\`

In alternativa, durante il bootstrap LAN puoi usare:

\`\`\`text
ws://192.168.1.112:3399
\`\`\`

Dal profilo Buzz recupera la tua \`npub\` personale. Poi inseriscila in
\`buzz.env\`:

\`\`\`env
RELAY_OWNER_PUBKEY=npub1...
\`\`\`

Sono accettati sia \`npub1...\` sia una chiave pubblica esadecimale di 64
caratteri. Riavvia \`axehero-buzz\`.

Verifica il log:

\`\`\`bash
docker logs --tail 100 axehero-buzz_relay_1
\`\`\`

Dovresti vedere un messaggio equivalente a:

\`\`\`text
relay CHIUSO — owner ...
\`\`\`

Da questo momento il relay richiede autenticazione NIP-42 e membership
esplicita.

## 5. Recuperare l’identità privata di Fizz dal Mac

Ogni agente Buzz ha una propria identità Nostr. La chiave privata di Fizz è un
\`nsec1...\` e non coincide con:

- la tua identità personale Buzz;
- la chiave pubblica \`npub\`;
- la chiave privata del relay;
- la API key di OmniRoute.

Buzz normalmente conserva le chiavi degli agenti nel Portachiavi di macOS e
non le scrive in chiaro in \`managed-agents.json\`.

Il file locale degli agenti è:

\`\`\`text
~/Library/Application Support/xyz.block.buzz.app/agents/managed-agents.json
\`\`\`

Da quel file recupera solo la \`pubkey\` pubblica associata al record di Fizz.
Non cercare una voce Portachiavi chiamata “Fizz”. In **Accesso Portachiavi**:

1. seleziona il portachiavi \`login\`;
2. cerca \`buzz-desktop\`;
3. apri l’elemento con account \`secrets\`;
4. autorizza **Mostra la password** con la password del Mac;
5. cerca la voce JSON \`agent:<pubkey-di-fizz>\`;
6. usa il valore \`nsec1...\` di quella voce come \`FIZZ_PRIVATE_KEY\`.

Il JSON completo può contenere anche l’identità personale. Non copiarlo in
chat, GitHub o in un issue. Se una chiave privata viene esposta, va considerata
compromessa e l’agente deve essere ricreato o ruotato.

## 6. Aggiungere Fizz al relay

La membership del relay e la membership dei canali sono due cose diverse.
Prima aggiungi la pubkey di Fizz al relay globale.

Il comando amministrativo deve caricare \`buzz.env\` e impostare l’URL pubblico;
un semplice \`docker exec ... buzz-admin\` può non vedere le variabili esportate
dallo script di bootstrap.

Sostituisci \`<FIZZ_PUBKEY_HEX>\` con la pubkey pubblica di Fizz:

\`\`\`bash
docker exec axehero-buzz_relay_1 bash -lc \\
  'set -a; . /config/buzz.env; set +a; \\
   export RELAY_URL=wss://team.smartinstitute.org; \\
   buzz-admin add-member \\
     --pubkey <FIZZ_PUBKEY_HEX> \\
     --role member'
\`\`\`

Verifica il roster:

\`\`\`bash
docker exec axehero-buzz_relay_1 bash -lc \\
  'set -a; . /config/buzz.env; set +a; \\
   export RELAY_URL=wss://team.smartinstitute.org; \\
   buzz-admin list-members'
\`\`\`

La pubkey di Fizz deve comparire con ruolo \`member\`.

Se il comando risponde che \`BUZZ_RELAY_PRIVATE_KEY\` manca, non modificare la
chiave: significa che il comando non ha caricato \`/config/buzz.env\`. Usa
esattamente la forma \`bash -lc\` mostrata sopra.

## 7. Installare \`axehero-buzz-agents\`

Dall’App Store AxeHero installa \`axehero-buzz-agents\`.

L’app ha come dipendenze:

- \`axehero-buzz\`;
- \`axehero-omniroute\`.

Al primo avvio può compilare i binari ARM64 upstream:

- \`buzz-acp\`;
- \`buzz-agent\`;
- \`buzz-cli\`;
- \`buzz-dev-mcp\`.

La prima compilazione può richiedere tempo, rete e diversi gigabyte temporanei.
Le partenze successive riusano i binari salvati nell’app-data.

Il file di configurazione viene creato in:

\`\`\`text
~/umbrel/app-data/axehero-buzz-agents/config/agents.env
\`\`\`

Il file non viene sovrascritto automaticamente durante gli aggiornamenti, così
le configurazioni esistenti non vengono cancellate.

## 8. Configurare \`agents.env\`

Modifica il file su Umbrel e inserisci i valori reali solo localmente:

\`\`\`env
BUZZ_RELAY_URL=wss://team.smartinstitute.org
BUZZ_API_TOKEN=

OMNIROUTE_API_KEY=<API_KEY_OMNIROUTE>
OMNIROUTE_BASE_URL=http://192.168.1.112:20128/v1
OMNIROUTE_API=chat
OMNIROUTE_MODEL=auto

FIZZ_PRIVATE_KEY=<NSEC_PRIVATA_DI_FIZZ>
FIZZ_MODEL=auto
FIZZ_SYSTEM_PROMPT=
FIZZ_AGENT_OWNER=<PUBKEY_HEX_DEL_PROPRIETARIO_RELAY>

HONEY_PRIVATE_KEY=
HONEY_MODEL=auto
HONEY_SYSTEM_PROMPT=

POLLEN_PRIVATE_KEY=
POLLEN_MODEL=auto
POLLEN_SYSTEM_PROMPT=
\`\`\`

Note:

- lascia vuoto \`HONEY_PRIVATE_KEY\` o \`POLLEN_PRIVATE_KEY\` se non vuoi avviarli;
- \`FIZZ_AGENT_OWNER\` deve essere la pubkey esadecimale di 64 caratteri del
  proprietario, non la \`npub1...\`;
- \`OMNIROUTE_MODEL=auto\` lascia a OmniRoute la scelta del provider/modello;
- \`OMNIROUTE_API=chat\` forza Chat Completions, utile per endpoint
  OpenAI-compatible non-OpenAI;
- \`BUZZ_API_TOKEN\` resta vuoto se il relay non richiede un token aggiuntivo;
- non aggiungere virgolette ai valori \`nsec1...\` o alle API key.

Proteggi il file:

\`\`\`bash
chmod 600 ~/umbrel/app-data/axehero-buzz-agents/config/agents.env
\`\`\`

## 9. Configurare l’owner-only correttamente

Il runner usa volutamente:

\`\`\`env
BUZZ_ACP_RESPOND_TO=owner-only
\`\`\`

Questo impedisce a Fizz di inoltrare al modello richieste provenienti da utenti
non autorizzati. Per funzionare, \`FIZZ_AGENT_OWNER\` deve essere valorizzato.

Se nei log compare:

\`\`\`text
no agent owner configured
respond-to=owner-only but no owner is set — all events will be dropped
\`\`\`

controlla che:

1. \`FIZZ_AGENT_OWNER\` esista in \`agents.env\`;
2. contenga 64 caratteri esadecimali;
3. corrisponda alla riga \`owner\` restituita da \`buzz-admin list-members\`;
4. l’app \`axehero-buzz-agents\` sia stata riavviata dopo la modifica.

Non cambiare automaticamente il filtro in \`anyone\` su un relay esposto a
internet. Usalo solo per un test temporaneo e consapevole.

## 10. Riavviare e verificare

Riavvia l’app \`axehero-buzz-agents\` dalla dashboard Umbrel oppure riavvia solo
il runner:

\`\`\`bash
docker restart axehero-buzz-agents_agent_runner_1
\`\`\`

Controlla lo stato:

\`\`\`bash
docker ps --filter name=axehero-buzz-agents
\`\`\`

Controlla i log:

\`\`\`bash
docker logs -f axehero-buzz-agents_agent_runner_1
\`\`\`

Per Fizz, la sequenza corretta contiene messaggi equivalenti a:

\`\`\`text
avvio Fizz con modello auto tramite OmniRoute
connected to relay at wss://team.smartinstitute.org
agent owner: <pubkey-owner>
discovered N channel(s)
subscribed to channel <uuid>
presence set to online
\`\`\`

Il log non deve contenere:

\`\`\`text
Auth failed: restricted: not a relay member
\`\`\`

Se compare, ripeti il passo 6.

## 11. Aggiungere Fizz ai canali

L’aggiunta al roster globale del relay non garantisce automaticamente la
presenza in ogni canale.

Dal client Buzz Desktop, usando l’identità proprietaria:

1. apri il canale desiderato;
2. apri le impostazioni o la gestione membri;
3. aggiungi Fizz come membro/bot;
4. riavvia il runner se il canale non compare subito nei log.

Nel log del runner controlla la riga:

\`\`\`text
discovered N channel(s)
\`\`\`

Se Fizz è membro del relay ma non di nessun canale, il numero può essere zero
oppure il canale desiderato può mancare dalle sottoscrizioni.

## 12. Verifica da iPhone

Sul client Buzz iPhone:

1. collega la stessa community Buzz;
2. usa il relay pubblico \`wss://team.smartinstitute.org\`;
3. completa il pairing tramite QR, se configurato;
4. aggiorna la schermata o riapri l’app;
5. verifica che Fizz risulti online;
6. menziona Fizz in un canale di cui è membro.

La presenza può richiedere alcuni secondi per propagarsi. Se il client mostra
ancora \`offline\`, chiudi e riapri la schermata del canale prima di concludere
che il runner sia fermo.

## 13. Diagnostica rapida

### Il container è in restart loop

Controlla:

\`\`\`bash
docker ps -a --filter name=axehero-buzz-agents
docker logs --tail 200 axehero-buzz-agents_agent_runner_1
\`\`\`

La prima compilazione ARM64 può essere lunga. La versione attuale del runner
mantiene il container vivo e applica un backoff, invece di uscire subito a ogni
errore.

### \`OMNIROUTE_API_KEY non impostata\`

Controlla che la chiave sia valorizzata in \`agents.env\` e che il file sia
quello montato dall’app:

\`\`\`text
~/umbrel/app-data/axehero-buzz-agents/config/agents.env
\`\`\`

Non stampare il file nei log o in chat.

### Errore OmniRoute con \`http://192.168.1.112:20128/v1\`

Verifica:

\`\`\`bash
docker ps --filter name=axehero-omniroute
docker logs --tail 100 axehero-omniroute_app_1
\`\`\`

Controlla che:

- OmniRoute sia \`healthy\`;
- il percorso finisca con \`/v1\`;
- la API key sia valida;
- \`OMNIROUTE_API=chat\` sia compatibile con il modello scelto;
- \`OMNIROUTE_MODEL=auto\` abbia almeno un provider disponibile.

### \`Auth failed: restricted: not a relay member\`

La chiave Fizz è stata letta, ma la pubkey non è nel roster del relay. Ripeti:

\`\`\`bash
docker exec axehero-buzz_relay_1 bash -lc \\
  'set -a; . /config/buzz.env; set +a; \\
   export RELAY_URL=wss://team.smartinstitute.org; \\
   buzz-admin add-member --pubkey <FIZZ_PUBKEY_HEX> --role member'
\`\`\`

Poi riavvia il runner.

### Fizz è online ma non risponde

Cerca nel log:

\`\`\`text
no agent owner configured
all events will be dropped
\`\`\`

Imposta \`FIZZ_AGENT_OWNER\` e riavvia il runner. Non usare \`anyone\` come scorciatoia
su un relay pubblico.

### Fizz è online ma non compare nel canale

Controlla che:

- Fizz sia membro del canale;
- il client iPhone sia collegato alla stessa community/domain authority;
- il log mostri il canale tra quelli sottoscritti;
- il client mobile sia stato aggiornato dopo la connessione dell’agente.

### L’app mostra Fizz offline dopo un riavvio

Controlla nell’ordine:

\`\`\`bash
docker ps --filter name=axehero-buzz-agents
docker logs --tail 100 axehero-buzz-agents_agent_runner_1
docker logs --tail 100 axehero-buzz_relay_1
\`\`\`

La prova decisiva è la presenza nel log del runner:

\`\`\`text
presence set to online
\`\`\`

Se compare, aggiorna il client iPhone. Se non compare, risolvi prima l’errore
precedente nel log.

## 14. Aggiornamenti

Prima di aggiornare:

1. esegui il backup di \`buzz.env\`;
2. conserva la \`BUZZ_RELAY_PRIVATE_KEY\` del relay;
3. conserva una copia sicura di \`agents.env\` fuori dal repository;
4. verifica che le chiavi private non siano state inserite in file versionati.

Dopo un aggiornamento:

\`\`\`bash
docker ps --filter name=axehero-buzz
docker ps --filter name=axehero-buzz-agents
docker logs --tail 100 axehero-buzz_relay_1
docker logs --tail 100 axehero-buzz-agents_agent_runner_1
\`\`\`

Il file \`agents.env\` deve rimanere persistente, ma le nuove variabili introdotte
da una release possono dover essere aggiunte manualmente. In particolare,
verifica sempre \`FIZZ_AGENT_OWNER\` dopo un aggiornamento.

## 15. Checklist finale

- [ ] OmniRoute installato e healthy.
- [ ] Provider LLM configurati in OmniRoute.
- [ ] Endpoint impostato a \`http://192.168.1.112:20128/v1\`.
- [ ] Relay Buzz installato e healthy.
- [ ] \`BUZZ_PUBLIC_HOST\` definitivo configurato prima dei canali.
- [ ] Reverse proxy con WebSocket attivo.
- [ ] Client Buzz collegato a \`wss://team.smartinstitute.org\`.
- [ ] \`RELAY_OWNER_PUBKEY\` configurato.
- [ ] Fizz presente nel roster globale del relay.
- [ ] Fizz presente nei canali desiderati.
- [ ] \`FIZZ_PRIVATE_KEY\` presente solo in \`agents.env\`/Portachiavi.
- [ ] \`FIZZ_AGENT_OWNER\` valorizzato con la pubkey owner in formato hex.
- [ ] \`OMNIROUTE_API_KEY\` presente ma mai committata.
- [ ] Log con \`connected to relay\` e \`presence set to online\`.
- [ ] Fizz visibile online da iPhone.
- [ ] Test di menzione completato.

## Riferimenti

- [Repository App Store AxeHero](https://github.com/pasmer/pro-umbrel-app-store)
- [Buzz upstream](https://github.com/block/buzz)
- [Buzz remote agents](https://github.com/block/buzz/blob/main/docs/remote-agents.md)
- [OmniRoute](https://github.com/diegosouzapw/OmniRoute)

