# JARVIS Mission Control

Headless web companion for the Hermes Agent Umbrel app.

## What it does

- Connects to Hermes through its authenticated API server.
- Keeps the Hermes API key on the server side.
- Streams Responses API events to the browser.
- Shows Hermes tool activity in the dashboard.
- Provides browser speech recognition and speech synthesis for a push-to-talk voice flow.
- Exposes explicit run creation and stop endpoints for future controls.

## Configuration on Umbrel

Create the key file in the app data directory before starting the app:

```bash
mkdir -p /home/umbrel/umbrel/app-data/axehero-jarvis-mission-control/data
printf '%s\n' 'YOUR_HERMES_API_KEY' \
  | sudo tee /home/umbrel/umbrel/app-data/axehero-jarvis-mission-control/data/hermes_api_key >/dev/null
sudo chmod 600 /home/umbrel/umbrel/app-data/axehero-jarvis-mission-control/data/hermes_api_key
```

The container connects to `http://hermes-agent_web_1:8642` on the Umbrel Docker
network. Do not publish Hermes port `8642` to the host; expose only the Jarvis
Mission Control app through Umbrel's proxy and Tailscale.

The compose file expects Umbrel's shared `umbrel_main_network` to exist. This
is the network reported by the installed Hermes container and lets Docker DNS
resolve `hermes-agent_web_1` without relying on its dynamic IP address.

## Local development

```bash
docker build -t jarvis-mission-control:local .
HERMES_API_KEY_FILE=/absolute/path/to/hermes_api_key \
  docker run --rm -p 8000:8000 \
  -e HERMES_API_URL=http://127.0.0.1:8642 \
  -e HERMES_API_KEY_FILE=/run/secrets/hermes_api_key \
  -v "$PWD/hermes_api_key:/run/secrets/hermes_api_key:ro" \
  jarvis-mission-control:local
```

The Umbrel app manifest and compose file are intentionally kept separate from
the current PyQt desktop entrypoint. This makes the web service safe to run
headlessly on the Raspberry Pi without changing the Mac experience.

## First Umbrel test

Copy this `mission_control` directory into a local Umbrel app-store directory
using the folder name `jarvis-mission-control`. Build the image on the
Raspberry Pi so it matches the device architecture:

```bash
cd /path/to/jarvis-mission-control
sudo docker build -t jarvis-mission-control:local .
```

Create the persistent API-key file before installing or starting the app:

```bash
sudo mkdir -p /home/umbrel/umbrel/app-data/jarvis-mission-control/data
printf '%s\n' 'YOUR_HERMES_API_KEY' \
  | sudo tee /home/umbrel/umbrel/app-data/jarvis-mission-control/data/hermes_api_key >/dev/null
sudo chmod 600 /home/umbrel/umbrel/app-data/jarvis-mission-control/data/hermes_api_key
```

Install the local app from the Umbrel App Store. Its proxy port is `18791`,
so the dashboard should be available at `http://umbrel.local:18791/` on the
LAN and at the equivalent Umbrel Tailscale address on the tailnet.

Before using it remotely, confirm that the Jarvis container is attached to
`umbrel_main_network` and that its health panel reports Hermes as connected.
