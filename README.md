# AxeHero Umbrel Community App Store

Benvenuto su **AxeHero**, un Community App Store per **umbrelOS**. Questa repository contiene una selezione di applicazioni e servizi self-hosted, configurati e ottimizzati appositamente per essere eseguiti sul tuo server Umbrel.

---

## 🚀 Come Installare l'App Store su Umbrel

Per aggiungere lo store **AxeHero** alla tua istanza di umbrelOS (versione 0.5 o superiore):

1. Accedi alla dashboard del tuo Umbrel (es. `http://umbrel.local`).
2. Apri l'**App Store**.
3. Clicca sui tre puntini in alto a destra o accedi alle impostazioni degli store.
4. Clicca su **Aggiungi Community Store** (Add Community Store).
5. Incolla l'URL di questa repository GitHub:
   ```text
   https://github.com/pasmer/pro-umbrel-app-store
   ```
6. Conferma. Lo store AxeHero e tutte le sue applicazioni compariranno immediatamente nell'interfaccia!

---

## 📦 Applicazioni Disponibili

Di seguito sono elencate le applicazioni incluse in questo App Store:

| Nome App | ID App | Porta | Categoria | Descrizione |
| :--- | :--- | :--- | :--- | :--- |
| **Portainer** | `axehero-portainer` | `9000` | Developer | Gestione semplificata di container Docker, stack e volumi. |
| **Listmonk** | `axehero-listmonk` | `9000` | Productivity | Gestore di mailing list e newsletter self-hosted ad alte prestazioni. |
| **Redash** | `axehero-redash` | `5000` | Data Science | Piattaforma per l'analisi dei dati e creazione di dashboard interattive. |
| **Collabora** | `axehero-collabora` | `5000` | Data Science | Suite per l'ufficio collaborativa online e modifica di documenti. |
| **Cloudflare Tunnel** | `cloudflared` | `4499` | Networking | Accesso sicuro alle app di Umbrel dall'esterno tramite Cloudflare. |
| **MariaDB** | `axehero-mariadb` | `9306` | Database | Database relazionale robusto derivato da MySQL. |
| **PhpMyAdmin** | `axehero-phpmyadmin` | `9855` | Database | Strumento web per l'amministrazione di MariaDB/MySQL. |
| **CreditRating PMI** | `axehero-rating-svm-web` | `8000` | Finance | Stima del rating creditizio delle PMI tramite algoritmi SVM (Machine Learning). |
| **Italy COVID-19 Dashboard** | `axehero-covid19-dashboard` | `8100` | Analytics | Dashboard interattiva Shiny (R) per l'analisi dei dati COVID-19 in Italia. |
| **WhatsappList** | `axehero-whatsapplist` | `7676` | Communication | Invio massivo e automatizzato di messaggi WhatsApp tramite file CSV. |
| **OmniRoute** | `axehero-omniroute` | `20128` | AI | Gateway locale unificato per accedere a molteplici provider LLM. |
| **Hello World** | `axehero-hello-world` | `4000` | Development | Applicazione demo e template di esempio per il community store. |
| *Postiz* | `axehero-postiz` | - | - | *In arrivo / In fase di sviluppo* |

---

## 🛠️ Contribuire e Sviluppare Nuove App

Se desideri aggiungere o modificare le applicazioni in questo store, consulta le nostre regole interne e linee guida dettagliate nel file [AGENTS.md](file:///Users/pasmer/Documents/App/pro-umbrel-app-store/AGENTS.md) (e in [.agents/AGENTS.md](file:///Users/pasmer/Documents/App/pro-umbrel-app-store/.agents/AGENTS.md)).

### Regole Chiave:
1. **Directory**: Ogni applicazione deve trovarsi in una directory dedicata con nome `axehero-<app-name>`.
2. **ID Manifest**: L'ID all'interno di `umbrel-app.yml` deve corrispondere esattamente al nome della cartella e includere il prefisso `axehero-`.
3. **Persistenza**: Tutti i volumi docker **devono** puntare a sotto-cartelle all'interno di `${APP_DATA_DIR}`. Non utilizzare volumi Docker anonimi o nominati nel blocco globale (es. `postgres_data:`).
4. **Porte**: Verifica che la porta definita in `umbrel-app.yml` coincida con quella esposta nel servizio principale del `docker-compose.yml` e che non generi conflitti con le altre applicazioni esistenti.
