# AI OS Dashboard for AxeHero

This Umbrel app runs the AI OS Dashboard 1.1.1 package from the owner's Mac.
The ZIP is not stored in this app-store repository. On first start the Umbrel
downloads it from 192.168.1.242:18776 and keeps the extracted package under
APP_DATA_DIR/source. The Mac must be on the same home network while the app
performs this first download. The transfer endpoint is restricted to the
Umbrel's LAN address 192.168.1.112 and serves only the named ZIP file.

The app's data/user directory is persisted under APP_DATA_DIR/user. The
upstream server stays bound to loopback inside its container. A small GET-only
gateway adapts Umbrel's reverse-proxy host headers to the upstream server's
loopback-only host check. Umbrel's app proxy provides the browser entry point.

The dashboard remains read-only, as in the upstream package. Its sample mode
works after startup. Importing a personal workspace requires placing/importing
it inside the app container, which this first version does not provide as a UI
workflow.
