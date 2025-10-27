#!/usr/bin/env bash
set -euo pipefail

# Environment variables
: "${PROXYSQL_ADMIN_USER:=admin}"
: "${PROXYSQL_ADMIN_PASSWORD:=$(openssl rand -base64 32)}"  # Auto-generate if not set
: "${POSTGRES_USER:=postgres}"
: "${POSTGRES_PASSWORD:=postgrespass}"
: "${REPMGR_USER:=repmgr}"
: "${REPMGR_PASSWORD:=repmgrpass}"
: "${PG_NODES:=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal,pg-4.railway.internal}"
: "${MONITOR_INTERVAL:=5}"
: "${APP_READONLY_PASSWORD:=$(openssl rand -base64 32)}"  # Read-only app user
: "${APP_READWRITE_PASSWORD:=$(openssl rand -base64 32)}"  # Read-write app user

log() { echo "[$(date -Iseconds)] [proxysql] $*"; }

# Generate ProxySQL config for PostgreSQL
generate_config() {
    cat > /etc/proxysql.cnf <<EOF
datadir="/var/lib/proxysql"

admin_variables=
{
    admin_credentials="${PROXYSQL_ADMIN_USER}:${PROXYSQL_ADMIN_PASSWORD}"
    pgsql_ifaces="127.0.0.1:6132"  # SECURITY: Localhost only, never expose publicly
}

pgsql_variables=
{
    threads=32
    max_connections=30000
    default_query_delay=0
    default_query_timeout=36000000
    have_compress=true
    poll_timeout=20000
    interfaces="0.0.0.0:5432"
    default_schema="postgres"
    stacksize=1048576
    server_version="17.0"
    monitor_username="${REPMGR_USER}"
    monitor_password="${REPMGR_PASSWORD}"
    monitor_history=600000
    monitor_connect_interval=60000
    monitor_ping_interval=10000
    monitor_read_only_interval=1500
    monitor_read_only_timeout=500
    ping_interval_server_msec=120000
    ping_timeout_server=500
    commands_stats=true
    sessions_sort=true
    connect_retries_on_failure=10
    multiplexing=true
}

pgsql_servers=
(
)

pgsql_users=
(
    {
        username = "${POSTGRES_USER}"
        password = "${POSTGRES_PASSWORD}"
        default_hostgroup = 1
        max_connections=5000
        default_schema="postgres"
        active = 1
    },
    {
        username = "${REPMGR_USER}"
        password = "${REPMGR_PASSWORD}"
        default_hostgroup = 1
        max_connections=100
        default_schema="repmgr"
        active = 1
    },
    {
        username = "app_readonly"
        password = "${APP_READONLY_PASSWORD}"
        default_hostgroup = 2
        max_connections=2000
        default_schema="postgres"
        active = 1
    },
    {
        username = "app_readwrite"
        password = "${APP_READWRITE_PASSWORD}"
        default_hostgroup = 1
        max_connections=3000
        default_schema="postgres"
        active = 1
    }
)

pgsql_query_rules=
(
    {
        rule_id=1
        active=1
        match_pattern="^SELECT.*FOR UPDATE"
        destination_hostgroup=1
        apply=1
        comment="Write queries to primary"
    },
    {
        rule_id=2
        active=1
        match_pattern="^(INSERT|UPDATE|DELETE|CREATE|DROP|ALTER|TRUNCATE)"
        destination_hostgroup=1
        apply=1
        comment="All writes to primary"
    },
    {
        rule_id=3
        active=1
        match_pattern="^SELECT"
        destination_hostgroup=2
        apply=1
        comment="Read queries to standbys"
    }
)

pgsql_replication_hostgroups=
(
    {
        writer_hostgroup=1
        reader_hostgroup=2
        comment="PostgreSQL cluster"
        check_type="read_only"
    }
)
EOF
    log "ProxySQL config generated for PostgreSQL"
}

# Discover and add PostgreSQL nodes
discover_nodes() {
    log "Discovering PostgreSQL nodes..."
    local nodes=(${PG_NODES//,/ })
    
    for node in "${nodes[@]}"; do
        local host="${node%:*}"
        local port="${node#*:}"
        [ "$host" = "$port" ] && port=5432
        
        log "Checking $host:$port"
        if timeout 5 pg_isready -h "$host" -p "$port" >/dev/null 2>&1; then
            # Check if primary or standby via admin interface (psql)
            local is_primary=$(PGPASSWORD="$REPMGR_PASSWORD" timeout 5 psql -h "$host" -p "$port" -U "$REPMGR_USER" -d postgres -tAc "SELECT NOT pg_is_in_recovery();" 2>/dev/null || echo "f")
            
            if [ "$is_primary" = "t" ]; then
                log "  → $host:$port is PRIMARY (hostgroup 1)"
                # Use psql to insert into pgsql_servers via admin interface
                PGPASSWORD="$PROXYSQL_ADMIN_PASSWORD" psql -h 127.0.0.1 -p 6132 -U "$PROXYSQL_ADMIN_USER" -d proxysql -c \
                    "INSERT INTO pgsql_servers(hostgroup_id,hostname,port,weight,max_connections) VALUES (1,'$host',$port,1000,100);" 2>/dev/null || true
            else
                log "  → $host:$port is STANDBY (hostgroup 2)"
                PGPASSWORD="$PROXYSQL_ADMIN_PASSWORD" psql -h 127.0.0.1 -p 6132 -U "$PROXYSQL_ADMIN_USER" -d proxysql -c \
                    "INSERT INTO pgsql_servers(hostgroup_id,hostname,port,weight,max_connections) VALUES (2,'$host',$port,1000,100);" 2>/dev/null || true
            fi
        else
            log "  → $host:$port is DOWN (skipping)"
        fi
    done
    
    # Load servers to runtime
    PGPASSWORD="$PROXYSQL_ADMIN_PASSWORD" psql -h 127.0.0.1 -p 6132 -U "$PROXYSQL_ADMIN_USER" -d proxysql -c "LOAD PGSQL SERVERS TO RUNTIME; SAVE PGSQL SERVERS TO DISK;" 2>/dev/null || true
    log "Nodes discovery completed"
}

# Monitor and update topology
monitor_topology() {
    log "Starting topology monitor (interval: ${MONITOR_INTERVAL}s)"
    while true; do
        sleep "$MONITOR_INTERVAL"
        
        # Clear current servers
        PGPASSWORD="$PROXYSQL_ADMIN_PASSWORD" psql -h 127.0.0.1 -p 6132 -U "$PROXYSQL_ADMIN_USER" -d proxysql -c "DELETE FROM pgsql_servers;" 2>/dev/null || true
        
        # Rediscover
        discover_nodes
    done
}

# Main
log "Starting ProxySQL 3.0.2 for PostgreSQL cluster"
generate_config

# Start ProxySQL
proxysql -f -c /etc/proxysql.cnf &
sleep 5

# Initial discovery
discover_nodes

# Start monitor in background
monitor_topology &

# Keep container running
wait
