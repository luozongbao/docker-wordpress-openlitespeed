#!/bin/sh
# Wrapper that runs wp-cli as the www-data user so callers don't need --allow-root.
# Installed by docker-compose into /usr/bin/wp (the real binary is moved to /usr/bin/wp.real).

WP_PATH="${WP_PATH:-/var/www/vhosts/localhost/html}"
WP_REAL="${WP_REAL:-/usr/bin/wp.real}"

exec runuser -u www-data -- "$WP_REAL" --path="$WP_PATH" "$@"
