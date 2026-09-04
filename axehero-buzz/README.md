# Buzz per umbrelOS — `axehero-buzz`

Relay [Buzz](https://github.com/block/buzz) self-hosted su umbrelOS, testato per Raspberry Pi 5 (arm64).

| | |
| :--- | :--- |
| **Immagine** | `ghcr.io/block/buzz:0.2.1` |
| **Porta Umbrel** | `3399` |
| **Pairing mobile** | `5001` (da esporre tramite reverse proxy HTTPS/WebSocket) |
| **Stack** | buzz-relay + buzz-pair-relay + PostgreSQL 17 + Redis 7 + MinIO |
| **RAM a regime** | ~1,5–2 GB |
| **Config** | `~/umbrel/app-data/axehero-buzz/config/buzz.env` |

---

## Cosa installa questa app (e cosa no)

Questa app installa **il relay**, cioè il server. È il pezzo che possiedi tu.

Il **client** è l'app desktop Buzz (Tauri) per macOS / Windows / Linux, che scarichi dalle
[release upstream](https://github.com/block/buzz/releases/latest) e configuri per puntare al tuo relay.

Aprendo la tile Buzz dalla dashboard di umbrelOS vedrai la **pagina di invito** servita dal relay,
non l'interfaccia di chat. Il client principale è l'app desktop Buzz; il pairing mobile usa il
servizio dedicato incluso nello stack.

---

## Setup

### 1. Installa e avvia

Dall'App Store AxeHero. Il primo avvio richiede qualche minuto: viene creato il database ed eseguite le migrazioni.

Al termine il relay è raggiungibile su `ws://umbrel.local:3399` in **modalità aperta** — chiunque sulla tua LAN può registrarsi. Va bene per il primo accesso; va chiuso prima di esporlo a internet.

### 2. Collega l'app desktop

Scarica il build per la tua piattaforma, poi lancialo puntando al tuo relay:

```bash
# macOS / Linux
BUZZ_RELAY_URL=ws://umbrel.local:3399 open -a Buzz
```

In alternativa cambia il relay dalle impostazioni dentro l'app.

Al primo avvio Buzz genera la tua identità Nostr. **Copia il tuo `npub`** dal profilo.

### 3. Chiudi il relay

Modifica `~/umbrel/app-data/axehero-buzz/config/buzz.env`:

```bash
RELAY_OWNER_PUBKEY=npub1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Accetta sia `npub1...` sia i 64 caratteri esadecimali — la conversione è automatica.

Riavvia l'app da umbrelOS. Nei log vedrai `relay CHIUSO — owner …`. Da ora servono
autenticazione NIP-42 e appartenenza esplicita al relay.

Per aggiungere altre persone:

```bash
docker exec axehero-buzz_relay_1 buzz-admin add-member --pubkey npub1... --role member
docker exec axehero-buzz_relay_1 buzz-admin list-members
```

### 4. Configura il dominio principale

Imposta l'hostname pubblico in `config/buzz.env`:

```bash
BUZZ_PUBLIC_HOST=buzz.miodominio.it
BUZZ_PUBLIC_TLS=true
```

> ⚠️ **Fallo prima di creare canali e messaggi.** Il relay usa l'host di `RELAY_URL` come identità
> della community ([`relay_url_authority`](https://github.com/block/buzz/blob/main/crates/buzz-core/src/tenant.rs)).
> Cambiarlo dopo non migra i dati: seminerà una community nuova e vuota, e i canali precedenti
> resteranno nel database ma irraggiungibili.

Configura un Proxy Host in Nginx Proxy Manager:

| Campo | Valore |
| :--- | :--- |
| Public hostname | `buzz.miodominio.it` |
| Forward scheme | `http` |
| Forward hostname/IP | indirizzo locale dell'Umbrel |
| Forward port | `3399` |
| WebSocket Support | attivo |
| SSL | certificato valido per `buzz.miodominio.it`, Force SSL attivo |

Usa l'indirizzo locale dell'Umbrel oppure un nome risolvibile da Nginx. Mantieni stabile
l'indirizzo IP tramite prenotazione DHCP, se possibile.

### 5. Configura il pairing mobile

Creare un secondo Proxy Host per il servizio pairing:

| Campo | Valore |
| :--- | :--- |
| Public hostname | `pair.buzz.miodominio.it` |
| Forward scheme | `http` |
| Forward hostname/IP | indirizzo locale dell'Umbrel |
| Forward port | `5001` |
| WebSocket Support | attivo |
| SSL | nuovo certificato per `pair.buzz.miodominio.it`, Force SSL attivo |

Il certificato del sottodominio `pair` deve includere esattamente quel nome. Un certificato
valido solo per il dominio principale non è sufficiente.

Poi aggiungi in `config/buzz.env`:

```bash
BUZZ_PAIRING_RELAY_URL=wss://pair.buzz.miodominio.it
```

Non aggiungere una policy di accesso interattiva davanti ai due endpoint: il client Buzz deve
completare direttamente l'handshake WebSocket e l'autenticazione NIP-42 del relay principale.

Riavvia l'app Buzz. Il documento NIP-11 del relay deve mostrare `pairing_relay_url` con l'URL
del sottodominio pairing. A quel punto il client desktop può generare il QR code e l'app mobile
può collegarsi.

---

## Note operative

**Backup.** `config/buzz.env` contiene `BUZZ_RELAY_PRIVATE_KEY`, la chiave con cui il relay firma
le liste di membri e i post creati via REST. Perderla significa che quelle firme non sono più
verificabili. Tutto sta sotto `APP_DATA_DIR`, quindi rientra nei backup di umbrelOS — ma tienine
una copia a parte.

**WebSocket.** Il reverse proxy deve inoltrare l'upgrade WebSocket sia per il relay principale sia
per il servizio pairing. L'autenticazione dell'app_proxy
di Umbrel è disattivata (`PROXY_AUTH_ADD: "false"`) perché intercetterebbe l'handshake NIP-42 prima
che Buzz lo veda: l'accesso è protetto dalla modalità chiusa del relay, non dalla password di Umbrel.
**Questo rende il passo 3 obbligatorio prima del passo 4.**

**Credenziali interne.** Postgres, Redis e MinIO usano password statiche e non pubblicano porte
sull'host: vivono solo sulla rete bridge interna dell'app. Solo il servizio `relay` è anche su
`umbrel_main_network`.

**Maturità.** Buzz è dichiaratamente alpha. Client mobile, gate di approvazione dei workflow e
notifiche push non sono ancora completi.

---

## Diagnostica

```bash
# Log del relay
docker logs -f axehero-buzz_relay_1

# Readiness (dentro il container, porta health separata)
docker exec axehero-buzz_relay_1 bash -c 'exec 3<>/dev/tcp/127.0.0.1/8080; \
  printf "GET /_readiness HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n" >&3; cat <&3'

# Stato dei servizi
docker ps --filter name=axehero-buzz
```

| Sintomo | Causa probabile |
| :--- | :--- |
| Il relay riparte in loop | Migrazioni fallite — controlla i log di `axehero-buzz_postgres_1` |
| `ERRORE DI CONFIGURAZIONE` nei log | `RELAY_OWNER_PUBKEY` malformato in `buzz.env` |
| I canali sono spariti dopo un cambio di dominio | Nuova community seminata: rimetti il vecchio `BUZZ_PUBLIC_HOST` |
| Il client desktop non si connette | Verifica che `BUZZ_PUBLIC_TLS` corrisponda a `ws://` o `wss://` usato dal client |
| `502` / `connection refused` sul relay | Proxy Host principale punta alla porta sbagliata: usa `3399` |
| QR mobile in errore `404` | Il Proxy Host pairing punta alla porta sbagliata: usa `5001` |
| Errore certificato sul pairing | Il certificato non contiene `pair.<dominio>` |
| `pairing_relay_url` assente dal documento NIP-11 | Manca `BUZZ_PAIRING_RELAY_URL` in `buzz.env` oppure l'app non è stata riavviata |

---

## Riferimenti

- [block/buzz](https://github.com/block/buzz) — repository upstream
- [ARCHITECTURE.md](https://github.com/block/buzz/blob/main/ARCHITECTURE.md) — design del sistema
- [deploy/compose](https://github.com/block/buzz/tree/main/deploy/compose) — bundle VPS di riferimento
- [Run your own Buzz relay](https://engineering.block.xyz/blog/run-your-own-buzz-relay) — blog Block
