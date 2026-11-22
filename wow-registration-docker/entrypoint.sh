#!/bin/bash
set -e

CONFIG_FILE="/var/www/html/application/config/config.php"

# config.php is bind-mounted read-only by docker-compose.yml and reads its
# addresses and database login from the environment (SITE_URL, HOST_IP,
# REGISTRATION_DB_USER, REGISTRATION_DB_PASSWORD), so nothing is written here.
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[entrypoint] ERROR: $CONFIG_FILE is missing; mount wow-registration-docker/config.php there" >&2
    exit 1
fi
if [ -z "${REGISTRATION_DB_PASSWORD:-}" ]; then
    echo "[entrypoint] WARNING: REGISTRATION_DB_PASSWORD is not set; the portal cannot log in to the database" >&2
fi
echo "[entrypoint] baseurl: ${SITE_URL:-http://localhost:8080}  realmlist: ${HOST_IP:-127.0.0.1}"

# Start Apache in the foreground (exec: Apache becomes PID 1 and gets SIGTERM)
exec apache2-foreground
