# AirTrail self-host overlay

This bundle runs AirTrail, Postgres, and Caddy from `/opt/airtrail` on a
Docker host. Only Caddy publishes a WAN port. AirTrail and Postgres
remain on private Docker networks, so neither port 3000 nor port 5432 is
reachable from the host or Internet.

## DNS prerequisite

Create only this DNS record (example hostname):

```text
airtrail.example.com  A  <your-server-ipv4>
```

Do not change unrelated DNS records for the zone. Port 443 must reach the server for
Caddy's TLS-ALPN certificate challenge. Port 80 is not required or published.

## Install

Copy this directory to the host, then install the non-secret files:

```sh
sudo install -d -m 755 /opt/airtrail
sudo install -m 644 compose.yml Caddyfile /opt/airtrail/
sudo install -m 644 airtrail.service /etc/systemd/system/airtrail.service
```

On the first install only, create the host-only environment file:

```sh
sudo install -m 600 .env.example /opt/airtrail/.env
sudoedit /opt/airtrail/.env
```

Replace both `replace_with_the_same_random_password` values with the same
random alphanumeric password. For example, generate one without printing it
into shell history with `openssl rand -hex 32`, then paste it into both
`DB_PASSWORD` and the password portion of `DB_URL`. Never commit `.env`.

Start the service:

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now airtrail.service
```

The named volumes `postgres-data`, `uploads`, `caddy-data`, and `caddy-config`
survive container recreation, service restarts, and `docker compose down`.
The one-shot `uploads-init` service makes the uploads volume writable by
AirTrail's UID 1000 before the application starts.

## Update

```sh
cd /opt/airtrail
sudo docker compose --env-file .env -f compose.yml pull
sudo systemctl reload airtrail.service
```

## Verify

```sh
sudo systemctl status airtrail.service --no-pager --full
sudo docker compose --env-file /opt/airtrail/.env -f /opt/airtrail/compose.yml ps
curl -fsSIL https://airtrail.example.com/login
sudo ss -lntup
```

There must be no host listener on port 3000.

## Backup Postgres

Write the dump outside the container so it remains available if the container
is replaced:

```sh
sudo install -d -m 700 /opt/airtrail/backups
sudo docker compose --env-file /opt/airtrail/.env -f /opt/airtrail/compose.yml \
  exec -T db pg_dump -U airtrail -d airtrail -Fc \
  | sudo tee /opt/airtrail/backups/airtrail-$(date -u +%Y%m%dT%H%M%SZ).dump >/dev/null
```

Restore with `pg_restore` only during a planned maintenance window.

## Invariants

- Do not publish the app port; HTTPS reverse proxy only.
- Keep AirTrail's port `3000` off the public internet.
- Never commit `/opt/airtrail/.env`, a database password, a DNS API token,
  or a personal FlightDiary CSV.

## DNS

The only DNS change for AirTrail is an A record for the public hostname,
for example:

| Type | Name | Content | Proxy status | TTL |
| --- | --- | --- | --- | --- |
| A | `airtrail` | `<your-server-ipv4>` | DNS only | Auto |

Use **DNS only** while Caddy obtains its first public certificate. It also
makes the required A-record target directly verifiable. A CDN proxy can
be evaluated later as a separate change.

Before changing DNS, capture existing records you must not alter:

```sh
dig +short MX example.com
dig +short TXT example.com
```

Add or edit only the `A` record for `airtrail.example.com`. Do not use a zone
import, change the nameservers, or modify unrelated records at the zone apex.

Verify the new host record and that unrelated records are unchanged:

```sh
dig +short @1.1.1.1 airtrail.example.com A
dig +short @1.1.1.1 example.com MX
dig +short @1.1.1.1 example.com TXT
```

The first command must return your server address. MX and other zone records
must match the values captured before the change. Once Caddy is live,
also verify `curl -fsS https://airtrail.example.com/api/ping`.

## Database and uploads backup

[`backup.sh`](./backup.sh) creates one private, timestamped backup directory
containing:

- `database.dump`: a compressed PostgreSQL custom-format dump;
- `uploads.tar.gz`: the contents of `/app/uploads` from the AirTrail container;
- `SHA256SUMS`: checksums for both files.

The script deliberately gets PostgreSQL credentials from the running database
container. It does not source `.env`, put a password on the command line, or
copy credentials into a backup.

Install it on the host and run the first backup manually:

```sh
sudo install -d -m 0700 /var/backups/airtrail
sudo install -d -m 0755 /opt/airtrail/bin
sudo install -m 0750 deploy/selfhost/backup.sh /opt/airtrail/bin/backup.sh
sudo /opt/airtrail/bin/backup.sh
```

The defaults are `/opt/airtrail` for the Compose project and
`/var/backups/airtrail` for output. They can be overridden without editing the
script:

```sh
sudo AIRTRAIL_DIR=/opt/airtrail BACKUP_ROOT=/mnt/offsite/airtrail \
  /opt/airtrail/bin/backup.sh
```

Schedule it daily from root's cron. Install this as
`/etc/cron.d/airtrail-backup` with mode `0644`:

```cron
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
17 3 * * * root /opt/airtrail/bin/backup.sh 2>&1 | logger -t airtrail-backup
```

Confirm the entry is installed with `sudo run-parts --test /etc/cron.daily`
only if it is placed in `cron.daily`; for the `cron.d` entry above, inspect
the next day's output with `journalctl -t airtrail-backup`. Retention and
off-host replication belong in the host's backup policy; the script never
deletes an older backup.

After every initial or changed setup, validate the newest backup without
restoring it:

```sh
backup_dir=/var/backups/airtrail/airtrail-YYYYMMDDTHHMMSSZ
cd "$backup_dir"
sha256sum --check SHA256SUMS
docker compose --project-directory /opt/airtrail exec -T db \
  pg_restore --list < database.dump >/dev/null
tar -tzf uploads.tar.gz >/dev/null
```

Copy backups off the host and perform a test restore before relying on
them. On a disposable AirTrail Compose stack, restore into an empty database
and unpack uploads into an empty directory:

```sh
docker compose exec -T db sh -eu -c \
  'createdb --username="$POSTGRES_USER" airtrail_restore_test'
docker compose exec -T db sh -eu -c \
  'pg_restore --exit-on-error --no-owner --no-acl \
    --username="$POSTGRES_USER" --dbname=airtrail_restore_test' \
  < database.dump
install -d -m 0700 restore-uploads
tar -xzf uploads.tar.gz -C restore-uploads
```

Inspect row counts and uploaded files, then discard the disposable stack. A
production restore is a separate, deliberate maintenance operation: stop
AirTrail, preserve the current database and uploads, restore both artifacts
from the same timestamp, then start the app and run the verification checklist
below. Never trial a restore against the live database.

## FlightDiary import verification

The source CSV is read-only and must remain outside this repository.
Do not commit real personal CSV files. Use anonymized fixtures only.

Import procedure:

1. Confirm that the signed-in AirTrail account is the intended owner and note
   its current flight count. For the initial import, that count must be zero.
2. Run `backup.sh` and validate its checksums before changing application data.
3. Open **Settings → Import → FlightRadar24**, select the source CSV, and start
   the import once.
4. Record the import summary immediately. If it reports an error or an
   unexpected count, do not retry: investigate or restore the pre-import
   backup first, because a retry can create duplicates.
5. Complete the checklist below.

After the importer reports success, verify all of the following in the GUI:

- [ ] Total flight count matches the source CSV data-row count.
- [ ] Earliest and latest flight dates match the source.
- [ ] The import summary reports no dropped or rejected rows.
- [ ] Several flights with a duration formatted as `HH:MM:SS` have sensible
      departure/arrival times and durations.
- [ ] No duplicate flights were introduced by a retry.
- [ ] A manual test flight can be created, saved, reopened, and deleted.

Finally verify from the host:

```sh
curl -fsS https://airtrail.example.com/api/ping
sudo ss -lntp
```

AirTrail must not be listening publicly on `:3000`, and HTTPS must work on `:443`.
