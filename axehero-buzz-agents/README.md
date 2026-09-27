# Buzz Agents per umbrelOS

Companion app per eseguire Fizz, Honey e Pollen sul Raspberry Pi, senza tenere
aperto Buzz Desktop sul Mac.

## Configurazione

Dopo il primo avvio, modifica:

```text
~/umbrel/app-data/axehero-buzz-agents/config/agents.env
```

Inserisci:

- `OMNIROUTE_API_KEY` — la chiave dell'endpoint OmniRoute;
- `OMNIROUTE_BASE_URL` — normalmente `http://192.168.1.112:20128/v1`;
- `OMNIROUTE_MODEL` — normalmente `auto`;
- `FIZZ_PRIVATE_KEY`, `HONEY_PRIVATE_KEY`, `POLLEN_PRIVATE_KEY` — le chiavi
  private Nostr dei rispettivi agenti;
- `BUZZ_API_TOKEN` — il token Buzz, se richiesto dal relay chiuso.

Se aggiorni un'installazione precedente, sostituisci `OPENROUTER_API_KEY` con
`OMNIROUTE_API_KEY` e imposta `OMNIROUTE_BASE_URL` e `OMNIROUTE_MODEL` nel file
esistente: il file sotto `app-data` non viene sovrascritto automaticamente.

I modelli preimpostati sono `auto`, `auto/coding`, `auto/fast` o qualunque
altro modello/alias pubblicato da OmniRoute. Lascia vuota una chiave privata
per disabilitare il relativo agente.

```text
Fizz  auto
Honey auto
Pollen auto
```

Il relay è già impostato su `wss://team.smartinstitute.org`. Gli agenti usano
le identità esistenti, quindi conservano i membri dei canali `Welcome` e
`pianificazione-smart` se vengono usate le chiavi private corrette.

## Avvio

La prima partenza compila i binari ARM64 upstream (`buzz-acp`, `buzz-agent`,
`buzz-cli` e `buzz-dev-mcp`) dentro l'app-data dell'app. Può richiedere tempo e
diversi gigabyte temporanei. Le partenze successive usano i binari già compilati.

Il runner avvia un processo separato per ogni agente configurato con riavvio
controllato e backoff. Honey deve
essere già membro di `pianificazione-smart`; la configurazione del runner non
modifica i membri dei canali.

## Verifica

```bash
docker ps --filter name=axehero-buzz-agents
docker logs -f axehero-buzz-agents_agent_runner_1
```

Non inserire mai le chiavi private o la chiave OmniRoute nel repository.
