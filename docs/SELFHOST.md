# Self-hosted AirTrail

Generic self-host overlay for this fork. See AGENTS.md.

## Deploy sketch

```
DNS example.com
  airtrail.example.com  A → <your server>
       │
       ▼
  Docker host
    caddy :443
    airtrail + postgres  (/opt/airtrail)
```

ORIGIN=`https://airtrail.example.com`. Publish HTTPS only. Do not publish the app port.

DNS, backup, and post-import procedures are documented in
[`deploy/selfhost/README.md`](../deploy/selfhost/README.md). The host-side backup
script is [`deploy/selfhost/backup.sh`](../deploy/selfhost/backup.sh).

## Acceptance

- [ ] https://airtrail.example.com login works
- [ ] Unrelated host DNS and services are left running
- [ ] Imported flights match the source CSV row count
- [ ] Manual new flight saves
- [ ] pg_dump exists
- [ ] App port 3000 is not on the WAN
