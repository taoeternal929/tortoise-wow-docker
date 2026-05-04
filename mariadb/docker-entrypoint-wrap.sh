#!/bin/bash

/usr/local/bin/docker-entrypoint.sh mariadbd &
MARIADB_PID=$!

echo ">>> Waiting for MariaDB to be ready..."
until mariadb -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1" &>/dev/null; do
  sleep 2
done

echo ">>> Updating realmlist address to: $HOST_IP"

mariadb -u root -p"${MYSQL_ROOT_PASSWORD}" <<EOF
USE tw_logon;
UPDATE realmlist SET address = '${HOST_IP}' WHERE name = 'TurtleWoW';
EOF

echo ">>> Realmlist updated successfully."

wait $MARIADB_PID
