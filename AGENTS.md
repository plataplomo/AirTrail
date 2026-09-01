# Agent Guide — plataplomo/AirTrail

Fork of [johanohly/AirTrail](https://github.com/johanohly/AirTrail) for a self-hosted flight logbook.

## Product

- Import FlightDiary CSV using the existing FR24-compatible importer.
- Deploy official AirTrail + Postgres with Docker Compose and Caddy for HTTPS.
- Publish only HTTPS. Keep the app and database off the WAN.
- Own GUI later. Do not rewrite the Svelte app unless needed for import.

See `docs/SELFHOST.md` and `deploy/selfhost/`.

## GitHub workflow

- `main` stays a clean sync root with upstream. Do not force-push `main`.
- Non-trivial work starts from a GitHub issue.
- Work on a task branch inside a git worktree, never on `main`.
- Deliver through a PR against `main`. Body must include `Closes #N`.
- Keep PRs scoped to one slice: import, deploy, or ops/docs.
- Signed commits required. Do **not** change `user.email`, `user.name`, `user.signingkey`, or `commit.gpgsign`.
- No secrets, `.env` passwords, or personal CSV files in git.
- Labels: task, enhancement, documentation, deployment, import, security, codex, priority: high/medium/low.

## Commands

```sh
git fetch origin
git checkout -b feat/<issue-slug>
# ...
git commit -S -m "feat: ..."
git push -u origin HEAD
gh pr create --base main --title "..." --body "Closes #N"
```
