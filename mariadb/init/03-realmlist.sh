#!/bin/bash
# This runs once on first database initialization.


echo ">>> Setting realmlist address to: $HOST_IP"

mariadb -u root -p"${MYSQL_ROOT_PASSWORD}" <<EOF
USE tw_logon;
UPDATE realmlist SET address = '${HOST_IP}' WHERE name = 'TurtleWoW';
EOF
