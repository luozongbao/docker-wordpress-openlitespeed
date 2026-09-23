# WordPress + OpenLiteSpeed Docker Stack

A self-contained, **production-ready** WordPress stack built on top of
**OpenLiteSpeed** (OLS) + **LSPHP** and **MariaDB**, all wired together with
`docker compose`.

This template is **project-agnostic** — drop any WordPress site into `www/`,
point it at any existing MariaDB volume, and you are ready to go.

---

## Why OpenLiteSpeed?

OpenLiteSpeed bundles **LSPHP (LiteSpeed PHP, a.k.a. LSAPI)** into the same
container as the web server — there is **no separate PHP-FPM container**.

| Stack                    | Containers | PHP runtime  | Notes                             |
| ------------------------ | ---------- | ------------ | --------------------------------- |
| **Old** Nginx + PHP-FPM  | 3          | PHP-FPM      | extra socket hop per request      |
| **New** OpenLiteSpeed    | 2          | LSPHP (LSAPI)| in-process PHP, `.htaccess`-native|

Other benefits:

- Built-in **HTTP/3** and **QUIC** support
- **LiteSpeed Cache** WordPress plugin compatibility
- Compatible with **Apache `htaccess`** rewrite rules
- Lower memory footprint (no FPM worker pool)

---

## Architecture

| Service      | Image                          | Role                                            |
| ------------ | ------------------------------ | ----------------------------------------------- |
| `wordpress`  | `litespeedtech/openlitespeed`  | Web server **+** LSPHP runtime (single image)   |
| `database`   | `mariadb:10.11`                | MariaDB — attaches to an external named volume  |

Both services share a user-defined bridge network (named
`<COMPOSE_PROJECT_NAME>_network` by default — see
[Running multiple stacks on one host](#running-multiple-stacks-on-one-host)
for how to customize this).

---

## File layout

```
.
├── docker-compose.yml          # 2-service stack definition
├── .env.example                # Template for environment variables (copy to .env)
├── .gitignore
├── .dockerignore
├── README.md                   # This file
├── database/                   # (empty) DB ships from the named volume
├── www/                        # Your WordPress document root
│                              # (bind-mounted into the OLS image at the
│                              #  default vhost docroot /var/www/vhosts/localhost/html)
└── logs/                       # OLS access + error logs (bind-mounted to
                               #  /usr/local/lsws/logs in the container)
```

> **No OLS config files are checked into this repo.** The image's built-in
> `localhost` vhost already points at `/var/www/vhosts/localhost/html` with
> an LSPHP handler and Apache-compatible `.htaccess` rewriting — which is
> exactly what WordPress needs. The stack only customizes the WebAdmin
> password on container start.

---

## Prerequisites

- Docker Engine 20.10+
- Docker Compose v2 (`docker compose` CLI)
- An existing MariaDB Docker named volume (or a SQL dump to bootstrap one)

> **Important:** the MariaDB data is held in an **external** Docker volume
> (named `${COMPOSE_PROJECT_NAME:-wp_ols}_db_data` by default). This repo
> never creates or destroys it — your data outlives the stack itself.

---

## Quick start

1. **Copy and edit your environment file:**

   ```bash
   cp .env.example .env
   nano .env
   ```

   Required variables:

   | Variable              | Description                                |
   | --------------------- | ------------------------------------------ |
   | `COMPOSE_PROJECT_NAME`| Stack namespace for containers / network / volumes (default: `wp_ols`) |
   | `DATABASENAME`        | Database name (must match `wp-config.php`) |
   | `DATABASEUSER`        | Database user                              |
   | `DATABASEPASS`        | Database password                          |
   | `MYSQL_ROOT_PASSWORD` | MariaDB root password                      |
   | `OLS_ADMIN_USER`      | OLS WebAdmin username (default: `admin`)   |
   | `OLS_ADMIN_PASSWORD`  | OLS WebAdmin password (default: `P@ssw0rd`)|

   Optional port overrides (defaults shown — only set these if the host
   port is already in use):

   | Variable        | Default | Description                          |
   | --------------- | ------- | ------------------------------------ |
   | `HTTP_PORT`     | `80`    | Host port for HTTP                   |
   | `HTTPS_PORT`    | `443`   | Host port for HTTPS                  |
   | `WEBADMIN_PORT` | `7080`  | Host port for the OLS WebAdmin       |
| `HTTP_PORT`           | Published HTTP port (default: `80`)         |
| `HTTPS_PORT`         | Published HTTPS port (default: `443`)       |
| `WEBADMIN_PORT`      | Published OLS WebAdmin port (default: `7080`)|
   ```bash
   docker compose up -d
   ```

   On first start the container's `command:` writes the OLS WebAdmin
   credentials to `/usr/local/lsws/admin/conf/htpasswd` using
   `openssl passwd -1`, so `OLS_ADMIN_USER` / `OLS_ADMIN_PASSWORD` from
   your `.env` are picked up automatically.

4. **Verify:**

   ```bash
   docker compose ps
   docker compose logs -f wordpress
   curl -I http://localhost
   ```

---

## OpenLiteSpeed on a production server

Most production hardening for OLS is about **not exposing the WebAdmin**
beyond `localhost`. This section walks through a safe, repeatable setup.

> **No OLS config files live in this repo** — the `litespeedtech/openlitespeed`
> image already ships a working `localhost` vhost with LSPHP and
> `.htaccess` rewriting. The stack only customizes the **WebAdmin password**
> on container start using the `OLS_ADMIN_USER` / `OLS_ADMIN_PASSWORD` env
> vars in `.env`.

### 1. Initial deployment checklist

- [ ] **Change the WebAdmin password** — set `OLS_ADMIN_USER` and
      `OLS_ADMIN_PASSWORD` in `.env` before the first `docker compose up`.
      The shipped default (`admin` / `P@ssw0rd`) is unsafe.
- [ ] **Restrict WebAdmin (port 7080)** — see "Hardening" below.
- [ ] **Disable 443 (HTTPS) listener** if you terminate TLS at a CDN
      (Cloudflare / Fastly / etc.). Otherwise add a real certificate —
      see "TLS".
- [ ] **Set real client IP** behind your CDN by enabling the
      `Use Client IP in Header` option in the OLS WebAdmin (the image's
      default vhost already has the right listener plumbing).
- [ ] **Rotate secrets** — never commit the real `.env` to version control.

### 2. Hardening the WebAdmin (port 7080)

By default `docker-compose.yml` publishes `7080` on `0.0.0.0`, which is
**not safe on a public server**. Choose one of the following patterns:

#### Option A — Bind WebAdmin to localhost only

Edit `docker-compose.yml` and replace the bare port with an explicit host IP
loopback binding:

```yaml
ports:
  - "127.0.0.1:7080:7080"   # only reachable from the server itself
```

Then reach it locally:

```bash
# On the server
curl -k https://127.0.0.1:7080
```

#### Option B — Don't publish 7080 at all, access via SSH tunnel (recommended)

Remove the `7080` mapping from `docker-compose.yml` entirely (or change it to
`127.0.0.1:7080:7080` to keep it bound to localhost on the host), then on
your **laptop**:

```bash
# Forward local port 7080 → remote 7080 over SSH
ssh -L 7080:127.0.0.1:7080 user@your-server.example.com
```

Open <https://localhost:7080> in your browser. The traffic stays on the
SSH channel — it is **encrypted and never reaches the public internet**.

Useful variations:

```bash
# Keep the tunnel alive through NAT / flaky networks
ssh -L 7080:127.0.0.1:7080 -o ServerAliveInterval=30 \
    -o ExitOnForwardFailure=yes user@your-server.example.com

# Use a custom local port
ssh -L 17080:127.0.0.1:7080 user@your-server.example.com

# Forward multiple admin ports through one session
ssh -L 7080:127.0.0.1:7080 -L 3306:127.0.0.1:3306 user@your-server.example.com

# As an ad-hoc SSH config entry
# ~/.ssh/config:
Host brk-prod
  HostName your-server.example.com
  User deploy
  LocalForward 127.0.0.1:7080 127.0.0.1:7080
  ServerAliveInterval 30
```

Then `ssh brk-prod` and open <https://localhost:7080>.

#### Option C — Firewall it

Keep `0.0.0.0:7080` published but restrict at the OS level with
`ufw` / `iptables` / a cloud security group:

```bash
# ufw — only allow your IP
sudo ufw allow from YOUR.PUBLIC.IP to any port 7080 proto tcp
sudo ufw deny 7080

# Or with iptables
sudo iptables -I DOCKER-USER -p tcp --dport 7080 ! -s YOUR.PUBLIC.IP -j DROP
```

### 3. Enabling TLS (optional, when not fronted by a CDN)

If you terminate TLS in OLS instead of in Cloudflare/etc., drop your key and
certificate into a path the OLS image can read and point the `HTTPS`
listener at them via the OLS WebAdmin (or `docker compose exec`):

```bash
# Generate a self-signed cert for testing
docker compose exec wordpress bash -c \
    "openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
     -keyout /usr/local/lsws/conf/vhosts/key.pem \
     -out    /usr/local/lsws/conf/vhosts/cert.pem \
     -subj '/CN=your-domain.example'"
```

Then update the `HTTPS` listener's `keyFile` / `certFile` in the WebAdmin
(Listener → HTTPS → SSL → Private Key / Certificate) to point at those
paths.

Reload OLS after the change:

```bash
docker compose exec wordpress /usr/local/lsws/bin/lswsctrl graceful
```

For production, prefer **Let's Encrypt** via `acme.sh` or a Cloudflare
Origin CA certificate (if fronted by Cloudflare).

### 4. Reverse-proxy / CDN real client IP

When sitting behind Cloudflare (or any reverse proxy that sets
`CF-Connecting-IP` / `X-Forwarded-For`), OLS needs to trust those headers.
In the OLS WebAdmin, go to **Virtual Host → localhost → General → Use
Client IP in Header** and set it to `1`.

This makes PHP / WordPress see the visitor's real IP rather than the proxy IP.

### 5. Graceful reloads (after editing configs)

```bash
# Pick up new OLS configs without dropping in-flight requests
docker compose exec wordpress /usr/local/lsws/bin/lswsctrl graceful

# Or restart the container (heavier)
docker compose restart wordpress
```

---

## Day-to-day commands

```bash
# Stack lifecycle
docker compose up -d
docker compose down          # keep DB volume
docker compose restart wordpress

# Logs
docker compose logs -f wordpress
docker compose logs -f database

# Shell access
docker compose exec wordpress bash
docker compose exec database bash

# Backup database
docker compose exec database mysqldump \
    -u root -p"${MYSQL_ROOT_PASSWORD:-rootpassword}" \
    ${DATABASENAME} > backup-$(date +%F).sql

# OpenLiteSpeed WebAdmin (after SSH tunnel)
# https://localhost:7080
```

---

## Configuration reference

### `docker-compose.yml`

| Field                 | Default                  | Notes                                  |
| --------------------- | ------------------------ | -------------------------------------- |
| `${HTTP_PORT:-80}:80` | published                | Public HTTP — host port via `HTTP_PORT` env (default `80`) |
| `${HTTPS_PORT:-443}:443` | published             | Public HTTPS — host port via `HTTPS_PORT` env (default `443`) |
| `${WEBADMIN_PORT:-7080}:7080` | **change to 127.0.0.1** | WebAdmin — host port via `WEBADMIN_PORT` env (default `7080`); see "Hardening" |
| `./www`               | bind mount               | WordPress docroot (`/var/www/vhosts/localhost/html` inside the container) |
| `./logs`              | bind mount               | OLS logs (`/usr/local/lsws/logs` inside the container) |
| `app-network`         | bridge network           | Internal service-to-service traffic — actual name `${COMPOSE_PROJECT_NAME:-wp_ols}_network` |
| External volume       | `<COMPOSE_PROJECT_NAME>_db_data` | Holds MariaDB data, never managed by this repo |

### `.env`

| Variable              | Description                                            |
| --------------------- | ------------------------------------------------------ |
| `COMPOSE_PROJECT_NAME`| Stack namespace used by Compose itself, plus all container, network, and volume names in this stack (default: `wp_ols`). Change it to run multiple copies of this stack on the same host without name collisions. |
| `DATABASENAME`        | MariaDB database name (matches `wp-config.php`)        |
| `DATABASEUSER`        | MariaDB user                                           |
| `DATABASEPASS`        | MariaDB password                                       |
| `MYSQL_ROOT_PASSWORD` | MariaDB root password (default: `rootpassword`)        |
| `OLS_ADMIN_USER`      | OLS WebAdmin username (default: `admin`)               |
| `OLS_ADMIN_PASSWORD`  | OLS WebAdmin password (default: `P@ssw0rd`)            |

The OLS image's built-in PHP (`/usr/local/lsws/lsphp8`) has a
`php.ini` preinstalled at `/usr/local/lsws/conf/php.ini`. To override
PHP settings, drop a custom file into `./www/php.ini` and add
`phpIniOverride { phpIni /var/www/vhosts/localhost/html/php.ini }`
in the WebAdmin under **Virtual Host → localhost → General** — or skip
the override and rely on the image defaults tuned for WordPress:

```ini
memory_limit = 256M
upload_max_filesize = 64M
post_max_size = 64M
max_execution_time = 300
```

---

## Running multiple stacks on one host

`docker-compose.yml` uses the `COMPOSE_PROJECT_NAME` variable from `.env` to
prefix **every** container, the bridge network, and every named volume in
this stack. The default (`wp_ols`) produces these resource names:

| Resource        | Name                              |
| --------------- | ------------------------------------- |
| App container   | `wp_ols_app`                        |
| DB container    | `wp_ols_db`                         |
| Network         | `wp_ols_network`                    |
| Volume (DB)     | `wp_ols_db_data`                    |
| Volume (OLS)    | `wp_ols_ls_conf`                    |
| Volume (admin)  | `wp_ols_admin_conf`                 |

To run a **second** copy of this stack on the same server (for a different
site), just clone the repo into a second folder, change
`COMPOSE_PROJECT_NAME` in **that** folder's `.env`, and bring it up. For
example, a project in `~/projects/site-b` might set:

```bash
COMPOSE_PROJECT_NAME=siteB
```

That stack then owns `siteB_app`, `siteB_db`, `siteB_network`,
`siteB_db_data`, `siteB_ls_conf`, and `siteB_admin_conf` — none of which
collide with the `wp_ols_*` resources of the first stack.

> ⚠️ **Note on host ports.** The stack still publishes `80`, `443`, and
> `7080` on the host by default. Two stacks cannot both bind to the same
> host port. If you run more than one stack on a single host, map the HTTP
> / HTTPS / WebAdmin ports to different host ports for the second stack
> (e.g. via the `HTTP_PORT`, `HTTPS_PORT`, and `WEBADMIN_PORT` env vars or
> by editing `docker-compose.yml`).

A few practical recipes:

```bash
# Stack A (existing) — uses the default COMPOSE_PROJECT_NAME=wp_ols
cd ~/projects/wp_ols
docker compose up -d

# Stack B (new) — different namespace + different host ports
cd ~/projects/site-b
sed -i 's/^COMPOSE_PROJECT_NAME=.*/COMPOSE_PROJECT_NAME=siteB/' .env
HTTP_PORT=8080 HTTPS_PORT=8443 WEBADMIN_PORT=7081 docker compose up -d
```

Down the line, all the usual commands respect the namespace too:

```bash
docker compose -p siteB ps
docker compose -p siteB logs -f
docker compose -p siteB down
```

---

## Troubleshooting

### `docker compose up` fails — "volume not found"

The expected external volume does not exist. The default name is
`<COMPOSE_PROJECT_NAME>_db_data` (where `COMPOSE_PROJECT_NAME` comes from
your `.env`, defaulting to `wp_ols`). Create one matching the value in
`docker-compose.yml`, or bootstrap a fresh one:

```bash
# Either bring the stack up — Docker will create the external volume for you —
docker compose up -d

# Or create it manually with the name expected by docker-compose.yml:
docker volume create "${COMPOSE_PROJECT_NAME:-wp_ols}_db_data"
docker compose up -d database
# Then import your SQL dump:
docker compose exec -T database mysql -u root -p"${MYSQL_ROOT_PASSWORD}" \
    ${DATABASENAME} < /path/to/dump.sql
```

### WordPress cannot reach the database

- Confirm `DATABASENAME` / `DATABASEUSER` / `DATABASEPASS` in `.env` match the
  values in `www/wp-config.php`.
- From inside the OLS container:

  ```bash
  docker compose exec wordpress bash -c \
      "mysql -h database -u ${DATABASEUSER} -p${DATABASEPASS} -e 'SHOW DATABASES;'"
  ```

### WebAdmin will not load over SSH tunnel

- Check the tunnel port is forwarded to **127.0.0.1** on the **remote** side.
- Confirm `7080` is bound inside the container:

  ```bash
  docker compose exec wordpress ss -tlnp | grep 7080
  ```
- If you removed the `7080` mapping, re-add it as
  `"127.0.0.1:7080:7080"` and re-tunnel.

### File permission issues in `www/`

LSPHP runs as `nobody:nogroup` inside the OLS image. WordPress still works
because the document root is bind-mounted and writable for the container's
UID/GID. To fix plugin/upload issues, ensure the host UID matches the
container UID or set up the `www-data` user manually:

```bash
docker compose exec --user root wordpress \
    chown -R nobody:nogroup /var/www/vhosts/localhost/html
```

### OLS keeps restarting / returns HTTP 503

This usually means LSPHP failed to fork. Check:

```bash
docker compose logs wordpress | tail -50
docker compose exec wordpress cat /usr/local/lsws/logs/error.log | tail -30
```

The most common causes are:

- A malformed `php.ini` in `./www` (e.g. invalid syntax) — temporarily
  remove it and restart.
- The host machine's `ulimit -n` is too low for the `Max Connections`
  setting in OLS. Bump it on the host: `ulimit -n 65535`.

### `wp-config.php` is missing

The image's docroot ships `wp-config-sample.php` only. Either:

- Copy it and edit values manually:

  ```bash
  cp www/wp-config-sample.php www/wp-config.php
  $EDITOR www/wp-config.php   # set DB_NAME / DB_USER / DB_PASSWORD / DB_HOST='database'
  ```

- Or open `http://localhost` in your browser and run the 5-minute WordPress
  installer (it will create `wp-config.php` for you).

---

## Recovery (if the DB volume is lost)

Recreate the external volume with the name expected by `docker-compose.yml`
(default: `${COMPOSE_PROJECT_NAME:-wp_ols}_db_data`), then import your
backup:

```bash
docker volume create "${COMPOSE_PROJECT_NAME:-wp_ols}_db_data"
docker compose up -d database

docker compose exec -T database mysql -u root -p"${MYSQL_ROOT_PASSWORD}" \
    ${DATABASENAME} < /path/to/backup.sql

docker compose up -d
```

---

## License

MIT. Use this stack in any project, commercial or otherwise.
