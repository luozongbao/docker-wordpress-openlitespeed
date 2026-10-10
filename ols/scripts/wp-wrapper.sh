#!/bin/sh
# Wrapper that runs wp-cli as the OLS PHP worker user (nobody:nogroup by default).
#
# The OLS image runs LSPHP as `nobody:nogroup`, so files written by wp-cli
# (plugin uploads, core updates, etc.) must be owned by the same user that
# the web server uses — otherwise the web server can't read them and
# WordPress keeps prompting for FTP credentials.
#
# The real wp-cli binary is moved to /usr/bin/wp.real by the entrypoint command
# in docker-compose.yml, and this script is symlinked from /usr/bin/wp.

set -eu

# Path defaults to the OLS default vhost docroot.
WP_PATH="${WP_PATH:-/var/www/vhosts/localhost/html}"

# Resolve the real wp-cli binary. Allow override via WP_REAL.
WP_REAL="${WP_REAL:-/usr/bin/wp.real}"

# Run-as user/group. OLS uses `nobody:nogroup`; override via env when needed
# (e.g. when the host bind-mount is owned by a different UID/GID).
WP_USER="${WP_USER:-nobody}"
WP_GROUP="${WP_GROUP:-nogroup}"

# When the requested user/group don't exist in the container (e.g. a custom
# UID/GID mount), fall back to the current uid/gid so wp-cli still works
# for the caller rather than failing silently.
if ! id -u "$WP_USER" >/dev/null 2>&1; then
  WP_USER="$(id -un)"
fi
if ! getent group "$WP_GROUP" >/dev/null 2>&1; then
  WP_GROUP="$(id -gn)"
fi

# Ensure the docroot exists and is readable before handing off to wp-cli.
if [ ! -d "$WP_PATH" ]; then
  echo "wp-wrapper: WP_PATH '$WP_PATH' does not exist or is not a directory" >&2
  exit 1
fi

exec runuser -u "$WP_USER" -- "$WP_REAL" --path="$WP_PATH" --allow-root "$@"
