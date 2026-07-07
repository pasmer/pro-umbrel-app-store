# Agent Rules for pro-umbrel-app-store

This file defines the project structure, configuration guidelines, and strict rules for AI agents modifying or adding applications to the **AxeHero Umbrel App Store**.

---

## 1. Project Overview & Architecture
This repository is an Umbrel Community App Store named **AxeHero** (`id: axehero`).
It hosts several self-hosted Dockerized applications configured specifically for the Umbrel platform.

### App Store Configuration
The store-wide configuration is defined in [umbrel-app-store.yml](file:///Users/pasmer/Documents/App/pro-umbrel-app-store/umbrel-app-store.yml):
- `id`: `"axehero"` (must match the folder prefix of all applications)
- `name`: `"AxeHero"`

---

## 2. Directory Structure of an App
Every application must be organized in its own subdirectory at the root level matching its full ID:
`axehero-<app-name>`

Inside each app directory, the following file structure is standard:
```
axehero-<app-name>/
├── umbrel-app.yml       # App manifest (metadata & integration config)
├── docker-compose.yml   # Docker services configuration
├── icon.png / icon.svg  # (Optional) Local icon asset
└── ...                  # (Optional) scripts, default-password, etc.
```

---

## 3. Strict Rules & Conventions

### 3.1 App Manifest (`umbrel-app.yml`)
- **ID Prefixing**: The `id` field must match the directory name exactly and must be prefixed with `axehero-`.
  - *Correct*: `id: axehero-whatsapplist`
  - *Incorrect*: `id: whatsapplist` (this will cause collisions or fail to load)
- **Port Mapping**: The `port` field defines the main port exposed to the host/user. Ensure it is unique across the repository.
- **Dependencies**: Specify any dependencies or leave as an empty list `dependencies: []`.
- **Default Credentials**: If the app has default credentials, specify `defaultUsername` and `defaultPassword`.

### 3.2 Docker Compose (`docker-compose.yml`)
- **Data Persistence**: 
  - **CRITICAL**: Do NOT use anonymous/named Docker volumes (e.g. `postgres_data:`) for persistence, as these are not backed up or restored correctly by Umbrel.
  - **Always** map persistent directories to paths within the `${APP_DATA_DIR}` environment variable.
  - *Correct*: `- ${APP_DATA_DIR}/data:/var/lib/mysql`
  - *Incorrect*: `- db_data:/var/lib/mysql`
- **Networking**:
  - Most apps should join the external `umbrel_main_network` to allow internal container communication.
  - Define it in the networks block:
    ```yaml
    networks:
      umbrel_main_network:
        external: true
    ```
- **Port Consistency**:
  - The port exposed under the `ports:` section of your primary service must match the `port:` specified in `umbrel-app.yml`.
  - *Example*: if `port` is `8100`, the compose must map `8100:8100` (or similar depending on internal routing).
- **Service & Container Names**:
  - Avoid hardcoding generic container names (e.g. `container_name: postgres`) to prevent namespace collisions on the host machine. Instead, prefix them with the app name (e.g., `container_name: axehero-redash-postgres` or let Docker compose name them naturally).

---

## 4. Current App Audit & Known Issues
When modifying existing apps, keep the following context in mind:

| App Path | App ID | Port | Notes / Observations |
| :--- | :--- | :--- | :--- |
| `axehero-cloudflared` | `cloudflared` | 4499 | **Anomaly**: Manifest ID does not follow the `axehero-` prefix convention. |
| `axehero-collabora` | `axehero-collabora` | 5000 | Has a hardcoded domain environment variable (`domain=cloud\\.merella\\.it`) and mismatching port mapping (`9980:9980`). |
| `axehero-redash` | `axehero-redash` | 5000 | Uses named volumes (`postgres_data`, `redis_data`) instead of persistent host paths under `${APP_DATA_DIR}`. |
| `axehero-postiz` | - | - | Empty directory. Needs to be populated or removed. |

---

## 5. Adding New Apps Workflow
1. Check the ports utilized by other apps in this repository to prevent collisions.
2. Create a folder named `axehero-<new-app>`.
3. Add `umbrel-app.yml` with:
   - `id: axehero-<new-app>`
   - Unique port
   - Valid metadata, including icons and categories.
4. Add `docker-compose.yml` referencing `${APP_DATA_DIR}` for all volumes.
5. Update `TO DO.md` or any tracking docs if necessary.
