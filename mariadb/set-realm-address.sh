#!/bin/sh
# Run by the one-shot `realmlist` service in docker-compose.yml, before realmd
# starts: store HOST_IP (from .env) as the realm's address, which realmd hands
# to clients so they can reach mangosd.
set -eu

case "$HOST_IP" in
  "" | *[!A-Za-z0-9.:-]*)
    echo "HOST_IP must be an IP address or host name, got '$HOST_IP'" >&2
    exit 1 ;;
esac
case "$REALM_NAME" in
  "" | *"'"* | *'\'*)
    echo "REALM_NAME must not be empty or contain quotes or backslashes" >&2
    exit 1 ;;
esac

sql() {
  mariadb -h mariadb -u"$MYSQL_USER" --password="$MYSQL_PASSWORD" \
    --batch --skip-column-names tw_logon -e "$1"
}

rows=$(sql "SELECT COUNT(*) FROM realmlist WHERE name = '$REALM_NAME'")
if [ "$rows" = 0 ]; then
  echo "No realm named '$REALM_NAME' in tw_logon.realmlist; set REALM_NAME in .env." >&2
  echo "Realms present:" >&2
  sql "SELECT id, name, address FROM realmlist" >&2
  exit 1
fi

sql "UPDATE realmlist SET address = '$HOST_IP' WHERE name = '$REALM_NAME'"
echo "realmlist: $(sql "SELECT CONCAT('realm ', id, ' (', name, ') -> ', address, ':', port) FROM realmlist WHERE name = '$REALM_NAME'")"
