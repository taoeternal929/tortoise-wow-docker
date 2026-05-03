# Tortoise WoW — Docker Compose Setup

A Docker Compose setup for running a [Tortoise WoW](https://github.com/Penqle/tortoise-wow) private server (based on MaNGOS Zero) using containerized services for MariaDB, `realmd`, and `mangosd`.

> **Credit:** All server source code belongs to the [Tortoise WoW project](https://github.com/Penqle/tortoise-wow). This repository only provides the Docker deployment configuration.

> **Compiled Executables** The two bundled executables (realmd/mangosd) are compiled on Ubuntu 25.10, minor changes are needed to fix Warden module and fit to a newer C++ compiler. The modified source code is here  [Tortoise WoW Dev](https://gitlab.thesageharbor.com/lurundao/tortoise-wow-dev).

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
- Server-side data files extracted from the 1.17.2 client
- An exported game database dump (see below)

> **About the binaries:** This project ships `realmd` and `mangosd` compiled natively on Linux for best performance. This is a **native Linux approach** — not Wine. The binaries run directly on the host kernel via Docker, giving you full performance without any Windows compatibility layer.

---

## Directory Structure

```
wow-server/
├── docker-compose.yml
├── realmd/
│   ├── Dockerfile
│   ├── realmd                  # compiled binary
│   └── realmd.conf
├── mangosd/
│   ├── Dockerfile
│   ├── mangosd                 # compiled binary
│   └── mangosd.conf
├── mariadb/
│   └── init/
│       ├── 01-grants.sql       # user permission grants
│       └── 02-mangos.sql.gz    # your exported database dump
└── data/
    ├── mysql/                  # mariadb data dir (auto-populated, do not touch)
    ├── dbc/
    ├── maps/
    ├── vmaps/
    ├── mmaps/
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

### 3. Database Dump

You need a full export of a working Tortoise WoW database. This can be generated from an existing database instance using the following command:

```bash
mysqldump \
  -h DB_IP_ADDRESS \
  -P DB_PORT \
  -u USERNAME \
  -pPASSWORD \
  --skip-ssl \
  --single-transaction \
  --routines \
  --triggers \
  --databases tw_char tw_logon tw_logs tw_world \
  | gzip > /tmp/mangos_dump_$(date +%F).sql.gz
```

Rename or copy the resulting file to:

```
mariadb/init/02-mangos.sql.gz
```

> The `mariadb/init/` directory is mounted as `docker-entrypoint-initdb.d`. MariaDB will automatically import all `.sql` and `.sql.gz` files in filename order on the **first startup** against an empty data directory.

---

## Configuration

### `realmd.conf`

Set the database connection to use the Docker service name `mariadb` as the host:

```ini
LoginDatabaseInfo = "mariadb;3306;mangos;mangos;realmd"
PatchesDir        = "/opt/realmd/patches"
```

### `mangosd.conf`

Similarly, use the service name for all three database connections:

```ini
WorldDatabaseInfo     = "mariadb;3306;mangos;mangos;mangos"
CharacterDatabaseInfo = "mariadb;3306;mangos;mangos;characters"
LoginDatabaseInfo     = "mariadb;3306;mangos;mangos;realmd"
DataDir               = "/opt/mangosd"
```

> **Important:** Never use `localhost`, `127.0.0.1`, or your host machine's LAN IP in config files. Docker resolves service names automatically within the internal network.

---

## First-Time Setup

```bash
# 1. Clone this repo and place your binaries, configs, data, and dump as described above

# 2. Build images and start all services
docker compose up --build -d

# 3. Follow logs to confirm successful database import and server startup
docker compose logs -f mariadb
docker compose logs -f realmd
docker compose logs -f mangosd
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

# 2. Wipe the MariaDB data directory
sudo rm -rf ./data/mysql/*

# 3. Replace the dump file
cp ~/mangos_dump_DATE.sql.gz ./mariadb/init/02-mangos.sql.gz

# 4. Bring services back up — init scripts run automatically on empty data dir
docker compose up -d
```
---
## Compiled binaries (release configuration)
**realmd** 
SHA256: 29af00243fbb6b41f9cd6ccd62ea42a1c753992fb434aa5a2fee63a347b7a209 
**mangosd** 
SHA256: 34665a89aa54beed7b6f579bbfc09ac76e66099dd2de514dc22c07969ae7293e

---

## Dependencies
```
ldd mangosd
        linux-vdso.so.1 (0x0000761ac0e04000)
        libACE-8.0.2.so => /lib/x86_64-linux-gnu/libACE-8.0.2.so (0x0000761abfa6b000)
        libmariadb.so.3 => /lib/x86_64-linux-gnu/libmariadb.so.3 (0x0000761ac0d9c000)
        libssl.so.3 => /lib/x86_64-linux-gnu/libssl.so.3 (0x0000761abf95f000)
        libcrypto.so.3 => /lib/x86_64-linux-gnu/libcrypto.so.3 (0x0000761abf200000)
        libz.so.1 => /lib/x86_64-linux-gnu/libz.so.1 (0x0000761ac0d7e000)
        libstdc++.so.6 => /lib/x86_64-linux-gnu/libstdc++.so.6 (0x0000761abee00000)
        libm.so.6 => /lib/x86_64-linux-gnu/libm.so.6 (0x0000761abf868000)
        libgcc_s.so.1 => /lib/x86_64-linux-gnu/libgcc_s.so.1 (0x0000761ac0d4f000)
        libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x0000761abea00000)
        libzstd.so.1 => /lib/x86_64-linux-gnu/libzstd.so.1 (0x0000761abf10f000)

ldd realmd
        linux-vdso.so.1 (0x000079cedb25a000)
        libACE-8.0.2.so => /lib/x86_64-linux-gnu/libACE-8.0.2.so (0x000079cedb025000)
        libmariadb.so.3 => /lib/x86_64-linux-gnu/libmariadb.so.3 (0x000079cedafc9000)
        libcrypto.so.3 => /lib/x86_64-linux-gnu/libcrypto.so.3 (0x000079ceda800000)
        libstdc++.so.6 => /lib/x86_64-linux-gnu/libstdc++.so.6 (0x000079ceda400000)
        libgcc_s.so.1 => /lib/x86_64-linux-gnu/libgcc_s.so.1 (0x000079cedaf9c000)
        libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x000079ceda000000)
        libm.so.6 => /lib/x86_64-linux-gnu/libm.so.6 (0x000079cedaea3000)
        libz.so.1 => /lib/x86_64-linux-gnu/libz.so.1 (0x000079cedae85000)
        libssl.so.3 => /lib/x86_64-linux-gnu/libssl.so.3 (0x000079ceda6f4000)
        libzstd.so.1 => /lib/x86_64-linux-gnu/libzstd.so.1 (0x000079ceda30f000)
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

# Database dumps
mariadb/init/*.sql.gz

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

Copyright (c) 2025 Taoeternal

This license applies solely to original contributions and modifications not directly created by the original creators.

Permission is granted to use, copy, modify, and distribute these contributions for **non-commercial purposes only**.

Attribution is not required.

**Commercial use of these contributions is prohibited.**

**Misrepresentation:** This software may not be represented as being authored, endorsed, or maintained by the original creators or any defunct entity associated with the original project.
