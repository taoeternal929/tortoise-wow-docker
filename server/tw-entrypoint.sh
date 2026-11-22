#!/bin/sh
# Entrypoint for the realmd and mangosd images.
#
# The server configs in this repo keep secrets out of git by using placeholders,
# e.g.  LoginDatabase.Info = "mariadb;3306;${MYSQL_USER};${MYSQL_PASSWORD};tw_logon"
# The servers cannot read environment variables themselves, so this script
# fills every ${NAME} in the file given with -c from the container's environment
# (docker-compose.yml passes the values from .env), writes the result next to the
# original, and then exec's the server so it runs as PID 1 and receives
# `docker stop`'s SIGTERM directly.
#
# A config without placeholders is used unchanged. A placeholder whose variable
# is not set is an error, so a missing .env value fails loudly at startup
# instead of as a confusing database login error.
set -eu

conf=""
prev=""
for a in "$@"; do
  [ "$prev" = "-c" ] && conf=$a
  prev=$a
done

if [ -n "$conf" ] && [ -f "$conf" ] && grep -q '\${[A-Za-z_][A-Za-z0-9_]*}' "$conf"; then
  rendered="$(dirname "$conf")/.rendered.$(basename "$conf")"
  if ! awk '
    {
      line = $0; out = ""
      while (match(line, /\$\{[A-Za-z_][A-Za-z0-9_]*\}/)) {
        name = substr(line, RSTART + 2, RLENGTH - 3)
        if (name in ENVIRON) { val = ENVIRON[name] } else { val = ""; missing[name] = 1 }
        out = out substr(line, 1, RSTART - 1) val
        line = substr(line, RSTART + RLENGTH)
      }
      print out line
    }
    END {
      for (n in missing) { printf "tw-entrypoint: %s is not set (used in the config); set it in .env\n", n > "/dev/stderr"; bad = 1 }
      exit bad
    }' "$conf" > "$rendered"; then
    rm -f "$rendered"
    exit 1
  fi
  chmod 600 "$rendered"
  # Swap the -c argument for the rendered file.
  swap=0
  for a do
    shift
    if [ "$swap" = 1 ]; then set -- "$@" "$rendered"; swap=0; continue; fi
    [ "$a" = "-c" ] && swap=1
    set -- "$@" "$a"
  done
fi

exec "$@"
