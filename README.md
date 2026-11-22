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
tortoise-wow-docker/
├── docker-compose.yml
├── .env.example                # copy to .env (not tracked) and fill in: addresses + passwords
├── server/
│   ├── Dockerfile              # builds realmd/mangosd/tools images from upstream source
│   ├── tw-entrypoint.sh        # fills ${...} placeholders in the server configs from .env
│   ├── upstream.env            # pinned upstream commit (updated by the sync workflow)
│   └── patches/                # our changes on top of upstream
├── .github/
│   ├── workflows/upstream-sync.yml
│   └── scripts/                # sync, database test and GitLab backup scripts
├── realmd/
│   └── realmd.conf             # DB login is ${MYSQL_USER}/${MYSQL_PASSWORD}
├── mangosd/
│   └── mangosd.conf            # DB logins are ${MYSQL_USER}/${MYSQL_PASSWORD}; RealmID = 2
├── mariadb/
│   ├── conf/my.cnf             # logging (errors -> docker logs, slow queries -> data/mysql/slow.log)
│   ├── set-realm-address.sh    # run by the one-shot `realmlist` service: realm address = HOST_IP
│   └── init/                   # run once, on an empty data/mysql
│       ├── 02-mangos_create_database_base_create_realmlist.sql.gz   # base databases, no accounts or characters
│       └── 03-users.sh         # database users with least privilege (passwords from .env)
├── wow-registration/           # submodule (upstream portal code, don't touch)
├── wow-registration-docker/    # portal Dockerfile, entrypoint and config.php
├── logs/
│   ├── realmd/                 # realmd log output
│   └── mangosd/                # mangosd log output
└── data/
    ├── mysql/                  # mariadb data dir (auto-populated, do not touch)
    ├── dbc/
    ├── maps/
    ├── vmaps/
    ├── mmaps/
    ├── database_updates/       # SQL migrations; mangosd applies new ones at startup
    └── patches/                # client patches loaded by realmd on auth
```
---

## Preparing Server Data

### 1. Game Data Folder

The `data/` directory must contain the following folders extracted from your client with the extractors (they are in the `tortoise-wow-tools` image, see [Automated builds](#automated-builds)):

- `dbc/` — client data tables
- `maps/` — terrain and map data
- `vmaps/` — visual/collision maps
- `mmaps/` — movement maps (pathfinding)

### 2. Patches

Place any client patch files into `data/patches/`. These are mounted into the `realmd` container and loaded during client authentication.

### 3. Database

This project ships with a **base database dump** (`mariadb/init/02-mangos_create_database_base_create_realmlist.sql.gz`) with all databases (`tw_logon`, `tw_char`, `tw_world`, `tw_logs`), the world data and one realm (`TurtleWoW`, id 2). It contains **no accounts and no characters**; create your own (see First-Time Setup).

Upstream world updates arrive in `data/database_updates/` through the sync pull requests; `mangosd` applies new ones automatically at startup.

> **Migrating from an existing server?** You can import your own dump instead, see [Migration](#migration--re-importing-the-database).

---

## Configuration

All site-specific values and passwords live in **`.env`**, which git does not track. Copy the template and fill it in:

```bash
cp .env.example .env
```

| Setting | Used for |
|---|---|
| `HOST_IP` | Your host's LAN IP. Written into the realm list on every start, so clients can reach mangosd. Containers stay on the internal `wow-net` network instead of the host network. |
| `SITE_URL` | Address of the registration portal, e.g. `http://192.168.1.x:8080`. |
| `MYSQL_ROOT_PASSWORD` | MariaDB root. Root can only log in from inside the `mariadb` container. |
| `MYSQL_USER` / `MYSQL_PASSWORD` | Login of realmd and mangosd: full access to the four `tw_*` databases, nothing else. |
| `REGISTRATION_DB_USER` / `REGISTRATION_DB_PASSWORD` | Login of the registration portal: create/update accounts, read characters, its own `votes` table. |
| `REALM_NAME` | Realm row whose address is set to `HOST_IP` (default `TurtleWoW`). |

`docker compose` refuses to start while a required value is missing. Avoid `;` in the passwords (the server configs use it as a separator).

The configs in the repo hold **no passwords**:

- `realmd/realmd.conf` and `mangosd/mangosd.conf` use `${MYSQL_USER}` / `${MYSQL_PASSWORD}`; the image entrypoint fills them in from the environment at startup.
- `wow-registration-docker/config.php` reads `SITE_URL`, `HOST_IP` and the portal login with `getenv()`.
- `mangosd.conf`'s `RealmID` must be the `id` of a row in `tw_logon.realmlist` (`2` for the shipped database); the portal's realm entry in `config.php` uses the same id. CI fails if they disagree.

The registration portal is [WoWSimpleRegistration](https://github.com/masterking32/WoWSimpleRegistration) by masterking32, pinned as the `wow-registration` submodule (clone with `--recurse-submodules`, or run `git submodule update --init`). It shares the `mariadb` container.

---

## First-Time Setup

```bash
# 1. Clone this repo with the portal submodule
git clone --recurse-submodules https://github.com/taoeternal929/tortoise-wow-docker
cd tortoise-wow-docker

# 2. Create .env and fill in HOST_IP, SITE_URL and the passwords
cp .env.example .env

# 3. Place your game data (dbc, maps, vmaps, mmaps) under data/

# 4. Pull the prebuilt server images, then start all services
#    (the registration portal image is built locally on first start)
docker compose pull realmd mangosd
docker compose up -d

# 5. Follow logs to confirm the database import and server startup
docker compose logs -f mariadb
docker compose logs -f realmd mangosd wow-registration

# 6. Create your first game account (optional; the portal can do it too)
docker attach wow-mangosd
# Press Enter — ">mangosd" prompt should appear
account create NAME PASSWORD
# Detach without stopping: Ctrl+P then Ctrl+Q

# 7. Open the registration portal: http://<your SITE_URL>
```

The first MariaDB start imports the dump, which takes about a minute.

---

## Upgrading an existing server

Changes that need a one-time step on a server set up before November 2026:

```bash
# 1. .env is no longer tracked: keep your values, then let git remove the old file
cp .env ~/tortoise-wow.env.backup
git checkout -- .env 2>/dev/null; git pull

# 2. Create the new .env from the template. Keep the passwords your database was
#    created with (from the backup: MYSQL_ROOT_PASSWORD, MYSQL_USER, MYSQL_PASSWORD),
#    copy HOST_IP and SITE_URL, and choose a new REGISTRATION_DB_PASSWORD.
cp .env.example .env && nano .env

# 3. Restart on the new setup and apply the new database users once
docker compose pull realmd mangosd
docker compose up -d mariadb
docker compose exec mariadb bash /docker-entrypoint-initdb.d/03-users.sh
docker compose up -d --build

# 4. Optional clean-up
rm -f logs/mariadb/general.log logs/mariadb/slow.log logs/mariadb/error.log
docker image rm tortoise-wow-docker-mariadb 2>/dev/null
```

`03-users.sh` limits the game login to the `tw_*` databases, creates the portal login, and removes the network-reachable `root@'%'` user that older versions created.

Step 3 replaces the old MariaDB container, which could not shut down cleanly (Docker killed it after 10 seconds on every stop). That happens one last time here; InnoDB recovers by itself on the next start. From then on MariaDB stops cleanly in about a second.

The shipped database used to contain a test account `123` (password `123`) with a character. Fresh installs no longer get it; on an existing server, delete it from the mangosd console if you don't use it: `account delete 123`.

## Changing database passwords

The passwords in `.env` are applied to a database only when it is created. To change them later:

- **Game or portal login:** edit `MYSQL_PASSWORD` / `REGISTRATION_DB_PASSWORD` in `.env`, then
  `docker compose up -d mariadb && docker compose exec mariadb bash /docker-entrypoint-initdb.d/03-users.sh && docker compose up -d`
- **Root:** change it in MariaDB first (`docker compose exec mariadb mariadb -uroot -p -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '...'"`), then put the same value in `.env`.

---

## Useful Commands

```bash
# Restart a single service after editing its .conf file (no rebuild needed)
docker compose restart realmd
docker compose restart mangosd

# Attach to the mangosd interactive console (for GM commands)
docker attach wow-mangosd
# Detach without stopping: Ctrl+P then Ctrl+Q

# View live logs (MariaDB errors are here too)
docker compose logs -f

# Stop all services (MariaDB and mangosd get up to 60 s to shut down cleanly)
docker compose down
```

---

## Migration / Re-importing the Database

To migrate to a new host or re-initialize the database with a fresh dump:

```bash
# 1. Stop services
docker compose down

# 2. Wipe the MariaDB data directory. Back it up first!
sudo rm -rf ./data/mysql/*

# 3. Optionally replace the provided dump with your own
rm ./mariadb/init/02-*.sql.gz
cp ~/your_mangos_dump.sql.gz ./mariadb/init/02-mangos_dump.sql.gz

# 4. Bring services back up — init scripts run automatically on an empty data dir
docker compose up -d
```

With your own dump, set `RealmID` in `mangosd.conf` (and the portal's realm id) to your realm's `id`, and `REALM_NAME` in `.env` to its name.

---
## Automated builds

`.github/workflows/upstream-sync.yml` replaces the manual merge → build → copy → commit loop.

**What it does** (daily, or when run by hand from the Actions tab):

1. Reads the tip of upstream `1181dev` (branch and repo are in `server/upstream.env`).
2. Compiles `realmd`, `mangosd` and the extractors with `server/Dockerfile`: upstream source at that commit plus `server/patches/*.patch`, on Ubuntu 26.04.
3. Publishes `ghcr.io/<owner>/tortoise-wow-{realmd,mangosd,tools}:<tag>`. The tag is `1181dev-<upstream commit>-<build id>`, where the build id is a hash of the build files in `server/` (Dockerfile, patches, entrypoint), so a tag always means the same source.
4. Tests the images: both servers must start (smoke test), then a stack test starts MariaDB from this repo's dump with the new images; realmd must serve logins and mangosd must connect to all four databases. (mangosd then stops at its map check, since CI has no client data.)
5. Opens (or updates) one pull request, `bot/upstream-sync`, that copies upstream's new SQL migrations into `data/database_updates/` and moves the pinned tag in `docker-compose.yml`. The PR lists new migrations, **warns about migrations upstream edited after release** (existing servers re-run those), lists config settings that differ from upstream's templates, and includes a **database check**: the new migrations are applied on top of the previous version exactly the way mangosd's auto-updater would, and any failure is shown (and put in the PR title) before you deploy.
6. Tags the exact built source in GitLab `tortoise-wow-dev` as `tw-<tag>` (see [GitLab copies](#gitlab-copies)).

Pushes to other branches only build, as a check; nothing is published.

**Deploying an update:** merge the PR, then on the server:

```bash
git pull
docker compose pull realmd mangosd
docker compose up -d
```

**One-time setup** (repository settings on GitHub):

- *Settings → Actions → General → Workflow permissions*: tick **Allow GitHub Actions to create and approve pull requests**.
- GitLab tokens as repository secrets: see [GitLab copies](#gitlab-copies).
- After the first publish, open each package under your GitHub profile → *Packages* and set its visibility to **Public** if it isn't already, so `docker compose pull` works without logging in.

**Building locally instead** (about 10 minutes on 4 cores): `docker compose build realmd mangosd`. The extractors are in the `tools` image:

```bash
docker run --rm -it -v /path/to/wow-client:/client ghcr.io/<owner>/tortoise-wow-tools:<tag> mapextractor
```

---
## GitLab copies

GitLab's own pull mirroring is a paid feature, so `.github/workflows/gitlab-mirror.yml` pushes the updates to GitLab instead. It keeps two projects current:

| GitLab project | Contents | When |
|---|---|---|
| `lurundao/tortoise-wow-docker` | an exact copy of this repo: every branch and tag | on every push and branch/tag deletion here, plus a full re-sync daily |
| `lurundao/tortoise-wow-dev` | `main` and `1181dev` = upstream tortoise-wow's branch **plus `server/patches/`** | hourly (and after every build) |

How `tortoise-wow-dev` is updated:

- Each update is one commit on top of the GitLab branch, with upstream's commit as a second parent, so the history reads "merge upstream into main/1181dev" and every push is a fast-forward (no force pushes; your earlier commits stay).
- The files are exactly upstream plus the patches. Fixes that upstream already has are not re-added (see `server/patches/README.md`).
- Every image build also tags its exact source as `tw-<image tag>`. A branch never moves back to an older upstream commit; backing up an older build only adds its tag.
- Branches other than `main` and `1181dev` are not touched. To follow different upstream branches, set the repository variable `GITLAB_FOLLOW_BRANCHES`, e.g. `["main", "1181dev", "dev"]`.

One-time setup (*GitHub repo → Settings → Secrets and variables → Actions*):

| Secret | GitLab token | Role | Scope |
|---|---|---|---|
| `GITLAB_TOKEN` | project access token of `tortoise-wow-dev` | **Maintainer** (`main` is a protected branch) | `write_repository` |
| `GITLAB_DOCKER_TOKEN` | project access token of `tortoise-wow-docker` | **Maintainer** | `write_repository` |

- Create the `tortoise-wow-docker` project on GitLab first, empty (no README). If you use one personal access token for both projects instead, store it in both secrets.
- If GitHub ever rewrites a branch's history (force push), GitLab refuses the update on a protected branch until you allow force push on it there.
- Optional variables `GITLAB_REPO_URL` and `GITLAB_DOCKER_REPO_URL` override the two project URLs.
- A missing secret skips that part with a warning instead of failing.

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
