# new_pg_cluster_clone

This is a safe clone of `/root/new_pg_cluster` created for testing and applying small fixes without touching the original project.

Files included:
- `entrypoint.sh` (patched: accepts `PRIMARY_HOST`, guards `NODE_ID` numeric, atomic write for `last_known_primary`)
- `monitor.sh` (patched: atomic write for `last_known_primary`)
- `docker-compose.yml` (copied)
- `Dockerfile` (copied)

Notes:
- The clone contains only low-risk changes meant to improve reliability while keeping behavior compatible.
- The original project in `/root/new_pg_cluster` was not modified.

Suggested next steps:
- Run `docker-compose up --build` in this clone to validate behavior.
- Optionally add healthchecks in the compose and tighten `pg_hba.conf` via env `ALLOWED_NETWORKS`.
