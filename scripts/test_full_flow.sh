#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Automated test script for full failover / fallback flow
# Usage: ./scripts/test_full_flow.sh
# Requires: docker, docker compose, containers named pg-1..pg-4 in compose

REPMGR_CONF=/etc/repmgr/repmgr.conf
PGDATA=/var/lib/postgresql/data
EXPECTED_NODES=4

log() { echo "[$(date -Iseconds)] [test] $*"; }

run_compose_up() {
  log "Bringing up cluster (docker compose up -d)"
  docker compose up -d
}

wait_for_nodes() {
  local timeout=${1:-180}
  local waited=0
  log "Waiting up to ${timeout}s for ${EXPECTED_NODES} nodes to register and be running"
  while [ $waited -lt $timeout ]; do
    status=$(docker exec pg-1 gosu postgres repmgr -f "$REPMGR_CONF" cluster show --csv 2>/dev/null || true)
    # count lines that look like node records (start with a digit)
    num_nodes=$(echo "$status" | grep -E '^[[:space:]]*[0-9]+' | wc -l || true)
    running_nodes=$(echo "$status" | grep -E ',[[:space:]]*running' | wc -l || true)
    if [ "$num_nodes" -ge "$EXPECTED_NODES" ] && [ "$running_nodes" -ge "$EXPECTED_NODES" ]; then
      log "All $EXPECTED_NODES nodes registered and running"
      return 0
    fi
    sleep 5
    waited=$((waited+5))
  done
  echo
  log "Timed out waiting for nodes (seen: $num_nodes, running: $running_nodes)" >&2
  return 1
}

current_primary_from_node() {
  local node=${1:-pg-1}
  docker exec "$node" gosu postgres repmgr -f "$REPMGR_CONF" cluster show --csv 2>/dev/null | awk -F',' 'tolower($3) ~ /primary/ {gsub(/"/,"",$2); print $2; exit}' || true
}

dump_last_known_primary() {
  log "Dumping /var/lib/postgresql/data/last_known_primary for all nodes"
  for node in pg-1 pg-2 pg-3 pg-4; do
    echo "--- $node ---"
    docker exec "$node" sh -c "[ -f $PGDATA/last_known_primary ] && cat $PGDATA/last_known_primary || echo '(missing)'" || echo "(error reading $node)"
    echo
  done
}

wait_for_promotion() {
  local expected_primary=$1
  local timeout=${2:-120}
  local waited=0
  log "Waiting up to ${timeout}s for $expected_primary to be primary"
  while [ $waited -lt $timeout ]; do
    p=$(current_primary_from_node pg-2)
    if [ "$p" = "$expected_primary" ]; then
      log "$expected_primary is primary"
      return 0
    fi
    sleep 3
    waited=$((waited+3))
  done
  log "Timed out waiting for promotion (current: $p)" >&2
  return 1
}

wait_for_rejoin_standby() {
  local node_to_check=$1
  local upstream=$2
  local timeout=${3:-180}
  local waited=0
  log "Waiting up to ${timeout}s for $node_to_check to rejoin as standby of $upstream"
  while [ $waited -lt $timeout ]; do
    status=$(docker exec "$upstream" gosu postgres repmgr -f "$REPMGR_CONF" cluster show --csv 2>/dev/null || true)
    line=$(echo "$status" | awk -F',' -v n="$node_to_check" '$2 ~ n {print tolower($3) "," tolower($4) "," $5}') || true
    if echo "$line" | grep -q 'standby'; then
      # ensure upstream matches
      up=$(echo "$line" | awk -F',' '{print $3}' | tr -d '" ')
      if [ "$up" = "$upstream" ] || [ -z "$up" ]; then
        log "$node_to_check is standby and attached to $upstream"
        return 0
      fi
    fi
    sleep 5
    waited=$((waited+5))
  done
  log "Timed out waiting for $node_to_check to rejoin as standby of $upstream" >&2
  return 1
}

main() {
  run_compose_up

  if ! wait_for_nodes 300; then
    log "Cluster nodes did not come up in time"; exit 2
  fi

  log "Initial cluster state:"; docker exec pg-1 gosu postgres repmgr -f "$REPMGR_CONF" cluster show || true
  dump_last_known_primary

  log "-- Step: Stop pg-1 to trigger failover --"
  docker stop pg-1

  # wait for promotion to pg-2
  if ! wait_for_promotion pg-2 180; then
    log "Promotion to pg-2 failed"; exit 3
  fi

  log "Cluster after failover:"; docker exec pg-2 gosu postgres repmgr -f "$REPMGR_CONF" cluster show || true
  dump_last_known_primary

  log "-- Step: Start pg-1 and wait for rejoin --"
  docker start pg-1
  if ! wait_for_rejoin_standby pg-1 pg-2 180; then
    log "pg-1 did not rejoin as standby"; exit 4
  fi
  docker exec pg-2 gosu postgres repmgr -f "$REPMGR_CONF" cluster show || true
  dump_last_known_primary

  log "-- Step: Full cluster restart to test fallback --"
  docker compose stop
  docker compose start

  if ! wait_for_nodes 180; then
    log "Cluster did not settle after full restart"; exit 5
  fi

  log "Cluster after full restart:"; docker exec pg-2 gosu postgres repmgr -f "$REPMGR_CONF" cluster show || true
  dump_last_known_primary

  # Verify that chosen primary equals last_known_primary on majority of nodes
  chosen=$(current_primary_from_node pg-2)
  log "Chosen primary after restart: $chosen"
  agree=0; total=0
  for node in pg-1 pg-2 pg-3 pg-4; do
    val=$(docker exec "$node" sh -c "[ -f $PGDATA/last_known_primary ] && cat $PGDATA/last_known_primary || echo '(missing)'") || val="(error)"
    total=$((total+1))
    if [ "$val" = "$chosen" ]; then agree=$((agree+1)); fi
  done

  log "Agreement: $agree of $total nodes have last_known_primary == $chosen"
  if [ $agree -ge $((total/2+1)) ]; then
    log "Fallback test PASSED"
    exit 0
  else
    log "Fallback test FAILED: insufficient agreement"; exit 6
  fi
}

main "$@"
