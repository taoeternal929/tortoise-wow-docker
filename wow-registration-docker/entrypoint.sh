#!/bin/bash
set -e

CONFIG_DIR="/var/www/html/application/config"
CONFIG_FILE="$CONFIG_DIR/config.php"
CONFIG_SAMPLE="$CONFIG_DIR/config.php.sample"

# Copy sample config if config.php doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    if [ -f "$CONFIG_SAMPLE" ]; then
        echo "[entrypoint] config.php not found — copying from config.php.sample"
        cp "$CONFIG_SAMPLE" "$CONFIG_FILE"
    else
        echo "[entrypoint] WARNING: Neither config.php nor config.php.sample found in $CONFIG_DIR"
    fi
else
    echo "[entrypoint] config.php already present — skipping copy"
fi

# Inject SITE_URL from environment variable if set
if [ -n "$SITE_URL" ]; then
    echo "[entrypoint] Setting baseurl to: $SITE_URL"
    sed "s|^\(\$config\['baseurl'\]\s*=\s*\).*|\1\"${SITE_URL}\";|" "$CONFIG_FILE" > /tmp/config.php.tmp \
        && cp /tmp/config.php.tmp "$CONFIG_FILE" \
        && rm /tmp/config.php.tmp
fi

# Start Apache in the foreground
exec apache2-foreground
