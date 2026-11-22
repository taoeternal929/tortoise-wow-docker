# Tortoise WoW — Docker Compose Setup

A Docker Compose setup for running a [Tortoise WoW](https://github.com/Penqle/tortoise-wow) private server (based on MaNGOS Zero) using containerized services for MariaDB, `realmd`, and `mangosd`.

> **Credit:** All server source code belongs to the [Tortoise WoW project](https://github.com/Penqle/tortoise-wow). This repository only provides the Docker deployment configuration. Regiseration php server code belongs to the [WoWSimpleRegistration] (https://github.com/masterking32/WoWSimpleRegistration)

> **Server images** `realmd` and `mangosd` are compiled from the upstream [tortoise-wow](https://github.com/tortoise-wow/tortoise-wow) source by GitHub Actions (see [Automated builds](#automated-builds)) and published to GHCR. The exact source of every build, upstream plus the patches in `server/patches/`, is backed up to [Tortoise WoW Dev](https://gitlab.thesageharbor.com/lurundao/tortoise-wow-dev) on GitLab.

---

## Services

| Service | Description | Port |
|---|---|---|
| `mariadb` | Database server | 3306 (internal) |
| `realmd` | Authentication / realm server | 3724 |
| `mangosd` | World server | 8085 |

---

## Prerequisites

- Docker & Docker Compose installed on the host
- Server-side data files extracted from the 1.18.1 client
- An exported game database dump (see below)

> **About the binaries:** `realmd` and `mangosd` are native Linux builds (Ubuntu 26.04 base image), not Wine. They run directly on the host kernel via Docker, giving you full performance without any Windows compatibility layer.

---

## Directory Structure

```
wow-server/
├── docker-compose.yml
├── .env                        # your host IP and DB credentials go here
├── server/
│   ├── Dockerfile              # builds realmd/mangosd/tools images from upstream source
│   ├── upstream.env            # pinned upstream commit (updated by the sync workflow)
│   └── patches/                # our changes on top of upstream
├── .github/
│   ├── workflows/upstream-sync.yml
│   └── scripts/                # sync + GitLab backup scripts used by the workflow
├── realmd/
│   └── realmd.conf
├── mangosd/
│   └── mangosd.conf
├── mariadb/
│   ├── Dockerfile
│   ├── docker-entrypoint-wrap.sh
│   ├── conf/
│   │   └── my.cnf              # MariaDB logging configuration
│   └── init/
│       ├── 01-grants.sql                                                # user permission grants
│       ├── 02-mangos_create_database_base_create_realmlist.sql.gz       # base database dump including create_database.sql, base/*.sql, realmlist.
│       └── 03-realmlist.sh 
├── wow-registration/          # submodule (upstream code, don't touch)
├── wow-registration-docker/   # Registeration docker/config files live here
│   ├── Dockerfile
│   ├── entrypoint.sh
│   └── config.php
├── logs/
│   ├── mariadb/                # MariaDB log output
│   ├── realmd/                 # realmd log output
│   └── mangosd/                # mangosd log output
└── data/
    ├── mysql/                  # mariadb data dir (auto-populated, do not touch)
    ├── dbc/
    ├── maps/
    ├── vmaps/
    ├── mmaps/
    ├── database_updates/       # server automatically picks up updates here
    └── patches/                # client patches loaded by realmd on auth
```
---

## Preparing Server Data

### 1. Game Data Folder

The `data/` directory must contain the following folders extracted from your client using the MaNGOS extraction tools:

- `dbc/` — client data tables
- `maps/` — terrain and map data
- `vmaps/` — visual/collision maps
- `mmaps/` — movement maps (pathfinding)

Place them under `data/` as shown in the directory structure above.

### 2. Patches

Place any client patch files into `data/patches/`. These are mounted into the `realmd` container and loaded during client authentication.

### 3. Database

This project ships with a **base database dump** (`mariadb/init/02-mangos_create_database_base_create_realmlist.sql.gz`) that includes:

- `create_database.sql` — creates all required databases and schemas
- `base/*.sql` — core world, logon, and character data
- Realmlist seed entry

This means **you do not need to port or export a database from an existing server** to get started. Simply follow the First-Time Setup steps below.

For ongoing world data updates, place SQL patch files into `data/database_updates/`. The `mangosd` server picks these up automatically at startup, keeping your world data in sync with upstream [Tortoise WoW](https://github.com/Penqle/tortoise-wow) releases without requiring a full re-import.

> **Migrating from an existing server?** You can still import your own dump by replacing `02-mangos_create_database_base_create_realmlist.sql.gz` with your own export. See [Migration](#migration--re-importing-the-database) below.

---

## Configuration

### `.env` Environmental Variables

Because `realmd` and `mangosd` run inside Docker's internal network (`wow-net`), WoW clients on your LAN need to know your **host machine's LAN IP** to connect. This IP is used to update the realmlist entry in the database at startup.

Auto-detecting the LAN IP from inside the container would require exposing containers to the host network, which introduces unnecessary security risk. Instead, you provide it explicitly via a `.env` file — this keeps containers fully isolated within `wow-net`.

`.env.example`:
```ini
# Your host machine's LAN IP (the IP other machines on your network use to reach this machine)
# To find it on Linux, run: ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}'
HOST_IP=192.168.1.x

# MariaDB credentials
MYSQL_ROOT_PASSWORD=yourRootPassword
MYSQL_USER=mangos
MYSQL_PASSWORD=mangos

# Registration portal — full URL (including port) that players will use to access it
# Use your host machine's LAN IP or a domain name
SITE_URL=http://192.168.1.x:8080
```
### `realmd.conf`

Set the database connection to use the Docker service name `mariadb` as the host:

```ini
LoginDatabaseInfo = "mariadb;3306;mangos;mangos;tw_logon"
PatchesDir        = "/opt/realmd/patches"
LogsDir           = "/opt/realmd/logs"
```

### `mangosd.conf`

Similarly, use the service name for all three database connections:

```ini
WorldDatabaseInfo     = "mariadb;3306;mangos;mangos;mangos"
CharacterDatabaseInfo = "mariadb;3306;mangos;mangos;characters"
LoginDatabaseInfo     = "mariadb;3306;mangos;mangos;realmd"
DataDir               = "/opt/mangosd"

# DB Auto-updater
Database.AutoUpdate.Enabled = 1
Database.AutoUpdate.Path = "/opt/mangosd/"
Database.AutoUpdate.AuthUpdateName = "unused"
Database.AutoUpdate.CharUpdateName = "unused"
Database.AutoUpdate.WorldUpdateName = "database_updates"
```
### `wow-registration/application/config/config.php`

The registration portal connects to the same `mariadb` container as the game server. Key settings:

```php
$config['db_host'] = 'mariadb';    // Docker service name — never use 127.0.0.1 or localhost
$config['db_name'] = 'tw_logon';
$config['db_user'] = 'mangos';
$config['db_pass'] = 'mangos';
$config['db_port'] = '3308';
$config['srp6_support'] = false;   // TurtleWoW/CMangos uses sha_pass_hash, not SRP6
```

> **`baseurl` is managed automatically** via the `SITE_URL` variable in `.env`. The entrypoint script injects it into `config.php` on every container start — you do not need to set it manually in `config.php`.

> **Important:** Never use `localhost`, `127.0.0.1`, or your host machine's LAN IP in config files. Docker resolves service names automatically within the internal network.

---
## WoW Simple Registration Portal Setup

The registration portal is based on [WoWSimpleRegistration](https://github.com/masterking32/WoWSimpleRegistration) by masterking32. It shares the existing `mariadb` database — no separate database container is needed.

### 1. Clone WoWSimpleRegistration into the subfolder

```bash
git clone https://github.com/masterking32/WoWSimpleRegistration wow-registration
```

### 2. Add the Docker files

Place the following files into the `wow-registration/` directory (they are provided in this repo):

- `Dockerfile` — builds a PHP 8.2 + Apache image with all required extensions (GMP, GD, ZIP, SOAP, Mbstring, PDO, PDO-MySQL) and runs `composer install` automatically at build time
- `entrypoint.sh` — copies `config.php.sample` on first run and injects `SITE_URL` at every startup

### 3. Create config.php

```bash
cp wow-registration/application/config/config.php.sample \
   wow-registration/application/config/config.php
```

Then edit `config.php` with the settings shown in the [Configuration](#wowregistrationapplicationconfigconfigphp) section above.

### 4. Set SITE_URL in .env

```
SITE_URL=http://192.168.1.x:8080
```

This is the only setting that changes between deployments — all asset URLs and form actions are derived from it automatically.

### Updating SITE_URL without rebuilding

If you change `SITE_URL` in `.env`, just restart the container — no rebuild needed:

```bash
docker compose restart wow-registration
```

### Verifying the portal is working

```bash
# Confirm baseurl was injected correctly from SITE_URL
docker exec -it wow-registration grep "baseurl" /var/www/html/application/config/config.php
```
## First-Time Setup

```bash
# 1. Clone this repo
git clone https://github.com/taoeternal929/tortoise-wow-docker
cd tortoise-wow-docker

# 2. Clone WoWSimpleRegistration into the wow-registration subfolder
git clone https://github.com/masterking32/WoWSimpleRegistration wow-registration

# 3. Copy and configure config.php for the registration portal
# Edit wow-registration-docker/config.php as described in Configuration above

# 4. Edit .env. according fto your HOST_IP, credentials, and SITE_URL

# 5. Place your game data (dbc, maps, vmaps, mmaps) under data/

# 6. Pull the prebuilt server images, then start all services
#    (mariadb and wow-registration are built locally on first start)
docker compose pull realmd mangosd
docker compose up -d

# 7. Follow logs to confirm successful database import and server startup
docker compose logs -f mariadb
docker compose logs -f realmd
docker compose logs -f mangosd
docker compose logs -f wow-registration

# 8. Attach to wow-mangosd to create your first game account (Optional)
docker attach wow-mangosd
# Press Enter — ">mangosd" prompt should appear
account create NAME PASSWORD

# 9. To detach without stopping: Ctrl+P then Ctrl+Q

# 10. Open the registration portal in your browser
#     http://<your SITE_URL>  (e.g. http://192.168.1.x:8080)
```

The MariaDB init process may take a few minutes on first run depending on the size of the database dump.

---

## Useful Commands

```bash
# Restart a single service after editing its .conf file (no rebuild needed)
docker compose restart realmd
docker compose restart mangosd

# Attach to the mangosd interactive console (for GM commands)
docker attach wow-mangosd
# Detach without stopping: Ctrl+P then Ctrl+Q

# View live logs
docker compose logs -f

# Stop all services
docker compose down
```

---

## Migration / Re-importing the Database

To migrate to a new host or re-initialize the database with a fresh dump:

```bash
# 1. Stop services
docker compose down

# 2. Wipe the MariaDB data directory. Remember to back befor doing so!
sudo rm -rf ./data/mysql/*

# 3. Remove provided dump and replace it with your dump file
rm ./mariadb/init/02-*.sql.gz
cp ~/your_mangos_dump.sql.gz ./mariadb/init/02-mangos_dump.sql.gz

# 4. Bring services back up — init scripts run automatically on empty data dir
docker compose up -d
```
---
## Automated builds

`.github/workflows/upstream-sync.yml` replaces the manual merge → build → copy → commit loop.

**What it does** (daily, or when run by hand from the Actions tab):

1. Reads the tip of upstream `1181dev` (branch and repo are in `server/upstream.env`).
2. Compiles `realmd`, `mangosd` and the extractors with `server/Dockerfile`: upstream source at that commit plus `server/patches/*.patch`, on Ubuntu 26.04.
3. Publishes `ghcr.io/<owner>/tortoise-wow-{realmd,mangosd,tools}:<tag>`. The tag is `1181dev-<upstream commit>-<build id>`, where the build id is a hash of the Dockerfile and patches, so a tag always means the same source.
4. Tests the images: both servers must start (smoke test), then a stack test starts MariaDB from this repo's dump with the new images; realmd must serve logins and mangosd must connect to all four databases. (mangosd then stops at its map check, since CI has no client data.)
5. Opens (or updates) one pull request, `bot/upstream-sync`, that copies upstream's new SQL migrations into `data/database_updates/` and moves the pinned tag in `docker-compose.yml`. The PR lists new migrations, **warns about migrations upstream edited after release** (existing servers re-run those), lists config settings that differ from upstream's templates, and includes a **database check**: the new migrations are applied on top of the previous version exactly the way mangosd's auto-updater would, and any failure is shown (and put in the PR title) before you deploy.
6. Pushes the exact built source to GitLab `1181dev` as a fast-forward commit (parents: previous GitLab head + the upstream commit) and tags it `tw-<tag>`.

Pushes to other branches only build, as a check; nothing is published.

**Deploying an update:** merge the PR, then on the server:

```bash
git pull
docker compose pull realmd mangosd
docker compose up -d
```

**One-time setup** (repository settings on GitHub):

- *Settings → Actions → General → Workflow permissions*: tick **Allow GitHub Actions to create and approve pull requests**.
- *Settings → Secrets and variables → Actions → New repository secret*: `GITLAB_TOKEN`, a GitLab project access token for `tortoise-wow-dev` with role **Developer** (Maintainer if `1181dev` is protected) and scope **write_repository**. Without it the GitLab step is skipped with a warning.
- Optional repository variables `GITLAB_REPO_URL` / `GITLAB_BRANCH` override the backup target.
- After the first publish, open each package under your GitHub profile → *Packages* and set its visibility to **Public** if it isn't already, so `docker compose pull` works without logging in.

**Building locally instead** (about 10 minutes on 4 cores): `docker compose build realmd mangosd`. The extractors are in the `tools` image:

```bash
docker run --rm -it -v /path/to/wow-client:/client ghcr.io/<owner>/tortoise-wow-tools:<tag> mapextractor
```

---
## `.gitignore` Recommendations

The following should not be committed to version control due to size or sensitivity:

```gitignore
# Large game data files
data/mysql/
data/maps/
data/vmaps/
data/mmaps/
data/dbc/
data/patches/
```

---

## Contributing

Please follow these guidelines when contributing:

- Do not target the latest major patch of Turtle WoW
- Test all contributions thoroughly before issuing a PR — DPSMate is a great tool to validate combat changes
- Always point to the issue you are resolving in your PR; if no issue exists, create one and label it appropriately
- Avoid direct spell edits — use `spell_affect`, `spell_proc_event`, `spell_scripts`, or backend code instead

---

## License

Copyright (c) 2026 Taoeternal

This license applies solely to original contributions and modifications not directly created by the original creators.

Permission is granted to use, copy, modify, and distribute these contributions for **non-commercial purposes only**.

Attribution is not required.

**Commercial use of these contributions is prohibited.**

**Misrepresentation:** This software may not be represented as being authored, endorsed, or maintained by the original creators or any defunct entity associated with the original project.
