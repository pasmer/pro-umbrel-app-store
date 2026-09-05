# Buzz Agents per umbrelOS

Companion app per eseguire Fizz, Honey e Pollen sul Raspberry Pi, senza tenere
aperto Buzz Desktop sul Mac.

## Configurazione

Dopo il primo avvio, modifica:

```text
~/umbrel/app-data/axehero-buzz-agents/config/agents.env
```

Inserisci:

- `OPENROUTER_API_KEY` — la chiave API OpenRouter;
- `FIZZ_PRIVATE_KEY`, `HONEY_PRIVATE_KEY`, `POLLEN_PRIVATE_KEY` — le chiavi
  private Nostr dei rispettivi agenti;
- `BUZZ_API_TOKEN` — il token Buzz, se richiesto dal relay chiuso.

I tre modelli preimpostati riflettono la configurazione rilevata dal client:

```text
Fizz  inclusionai/ling-3.0-flash-sante:free
Honey z-ai/glm-5.3-flash
Pollen z-ai/glm-5.3-flash
```

Il relay è già impostato su `wss://team.smartinstitute.org`. Gli agenti usano
le identità esistenti, quindi conservano i membri dei canali `Welcome` e
`pianificazione-smart` se vengono usate le chiavi private corrette.

## Avvio

La prima partenza compila i binari ARM64 upstream (`buzz-acp`, `buzz-agent`,
`buzz-cli` e `buzz-dev-mcp`) dentro l'app-data dell'app. Può richiedere tempo e
diversi gigabyte temporanei. Le partenze successive usano i binari già compilati.

Il runner avvia tre processi separati con `restart: unless-stopped`. Honey deve
essere già membro di `pianificazione-smart`; la configurazione del runner non
modifica i membri dei canali.

## Verifica

```bash
docker ps --filter name=axehero-buzz-agents
docker logs -f axehero-buzz-agents_agent_runner_1
```

Non inserire mai le chiavi private o la chiave OpenRouter nel repository.
