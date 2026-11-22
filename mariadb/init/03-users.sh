#!/bin/bash
# Database users, with only the access each one needs. Passwords come from .env.
#
#  - MYSQL_USER (game servers): everything on tw_logon, tw_char, tw_world and
#    tw_logs, nothing else.
#  - REGISTRATION_DB_USER (web portal, the only part reachable over HTTP):
#    read/create/update accounts, its own `votes` table, read-only characters.
#  - root: local to the database container only (no root@'%').
#
# MariaDB runs this once by itself, on first start with an empty data dir
# (after 02 has imported the dump). It is safe to run again, which is how an
# existing database is brought up to date, e.g. after changing a password in .env:
#
#   docker compose exec mariadb bash /docker-entrypoint-initdb.d/03-users.sh
set -euo pipefail

: "${MYSQL_ROOT_PASSWORD:?}" "${MYSQL_USER:?}" "${MYSQL_PASSWORD:?}" "${REGISTRATION_DB_PASSWORD:?}"
REGISTRATION_DB_USER=${REGISTRATION_DB_USER:-wowreg}

# Escape a value for use inside a single-quoted SQL string.
q() { local s=${1//\\/\\\\}; printf '%s' "${s//\'/\\\'}"; }
u=$(q "$MYSQL_USER"); p=$(q "$MYSQL_PASSWORD")
ru=$(q "$REGISTRATION_DB_USER"); rp=$(q "$REGISTRATION_DB_PASSWORD")

if [ "$MYSQL_USER" = "$REGISTRATION_DB_USER" ]; then
  echo "03-users: MYSQL_USER and REGISTRATION_DB_USER must be different users" >&2
  exit 1
fi

# Older versions of this repo created 'mangos'@'%' with ALL PRIVILEGES ON *.*.
# If the game servers now use a different user, remove that one.
legacy=""
if [ "$MYSQL_USER" != "mangos" ]; then
  legacy="DROP USER IF EXISTS 'mangos'@'%';"
fi

if ! mariadb --protocol=socket -uroot --password="$MYSQL_ROOT_PASSWORD" <<SQL
CREATE USER IF NOT EXISTS '$u'@'%' IDENTIFIED BY '$p';
ALTER USER '$u'@'%' IDENTIFIED BY '$p';
REVOKE ALL PRIVILEGES, GRANT OPTION FROM '$u'@'%';
GRANT ALL PRIVILEGES ON \`tw_logon\`.* TO '$u'@'%';
GRANT ALL PRIVILEGES ON \`tw_char\`.*  TO '$u'@'%';
GRANT ALL PRIVILEGES ON \`tw_world\`.* TO '$u'@'%';
GRANT ALL PRIVILEGES ON \`tw_logs\`.*  TO '$u'@'%';

CREATE USER IF NOT EXISTS '$ru'@'%' IDENTIFIED BY '$rp';
ALTER USER '$ru'@'%' IDENTIFIED BY '$rp';
REVOKE ALL PRIVILEGES, GRANT OPTION FROM '$ru'@'%';
GRANT SELECT, INSERT, UPDATE ON \`tw_logon\`.\`account\` TO '$ru'@'%';
GRANT CREATE, SELECT, INSERT, UPDATE, DELETE ON \`tw_logon\`.\`votes\` TO '$ru'@'%';
GRANT SELECT ON \`tw_char\`.* TO '$ru'@'%';

$legacy
DROP USER IF EXISTS 'root'@'%';
FLUSH PRIVILEGES;
SQL
then
  echo "03-users: could not log in as root. MYSQL_ROOT_PASSWORD in .env must be the" >&2
  echo "root password this database was created with." >&2
  exit 1
fi
echo "03-users: '$MYSQL_USER' -> tw_logon/tw_char/tw_world/tw_logs; '$REGISTRATION_DB_USER' -> portal tables only; no remote root"
