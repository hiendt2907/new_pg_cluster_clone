#!/usr/bin/env bash
set -euo pipefail

# Environment variables
: "${POSTGRES_USER:=postgres}"
: "${POSTGRES_PASSWORD:=postgrespass}"
: "${REPMGR_USER:=repmgr}"
: "${REPMGR_PASSWORD:=repmgrpass}"
: "${PG_NODES:=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal,pg-4.railway.internal}"
: "${PGPOOL_PORT:=5432}"
: "${PGPOOL_PCP_PORT:=9898}"
: "${HEALTH_CHECK_INTERVAL:=10}"

log() { echo "[$(date -Iseconds)] [pgpool] $*"; }

# Generate pgpool.conf
generate_pgpool_conf() {
    local nodes=(${PG_NODES//,/ })
    local num_nodes=${#nodes[@]}
    
    cat > /etc/pgpool2/pgpool.conf <<EOF
# Connection Settings
listen_addresses = '*'
port = ${PGPOOL_PORT}
socket_dir = '/var/run/postgresql'
pcp_listen_addresses = '*'
pcp_port = ${PGPOOL_PCP_PORT}
pcp_socket_dir = '/var/run/postgresql'

# Backend Settings
backend_clustering_mode = 'streaming_replication'
num_init_children = 32
max_pool = 4
child_life_time = 300
child_max_connections = 0
connection_life_time = 0
client_idle_limit = 0

# Load Balancing
load_balance_mode = on
ignore_leading_white_space = on
white_function_list = ''
black_function_list = 'nextval,setval,nextval,lastval,currval'

# Streaming Replication
sr_check_period = 10
sr_check_user = '${REPMGR_USER}'
sr_check_password = '${REPMGR_PASSWORD}'
sr_check_database = 'postgres'
delay_threshold = 10000000

# Health Check
health_check_period = ${HEALTH_CHECK_INTERVAL}
health_check_timeout = 20
health_check_user = '${REPMGR_USER}'
health_check_password = '${REPMGR_PASSWORD}'
health_check_database = 'postgres'
health_check_max_retries = 3
health_check_retry_delay = 1

# Failover
failover_command = ''
failback_command = ''
fail_over_on_backend_error = off
search_primary_node_timeout = 300

# Logging
log_destination = 'stderr'
log_line_prefix = '%t: pid %p: '
log_connections = on
log_hostname = on
log_statement = off
log_per_node_statement = off
log_client_messages = off
log_standby_delay = 'if_over_threshold'

# Memory
memqcache_method = 'shmem'
memqcache_memqcache_total_size = 67108864
memqcache_max_num_cache = 1000000
memqcache_expire = 0
memqcache_auto_cache_invalidation = on
memqcache_maxcache = 409600
memqcache_cache_block_size = 1048576

# Backend nodes (will be dynamically added)
EOF

    # Add backend nodes
    local idx=0
    for node in "${nodes[@]}"; do
        local host="${node%:*}"
        local port="${node#*:}"
        [ "$host" = "$port" ] && port=5432
        
        cat >> /etc/pgpool2/pgpool.conf <<EOF

# Backend $idx
backend_hostname$idx = '$host'
backend_port$idx = $port
backend_weight$idx = 1
backend_data_directory$idx = '/var/lib/postgresql/data'
backend_flag$idx = 'ALLOW_TO_FAILOVER'
backend_application_name$idx = 'pg-${idx}'
EOF
        ((idx++))
    done
    
    log "Generated pgpool.conf with $num_nodes backends"
}

# Generate pool_passwd
generate_pool_passwd() {
    mkdir -p /etc/pgpool2
    echo "${POSTGRES_USER}:$(echo -n "${POSTGRES_PASSWORD}${POSTGRES_USER}" | md5sum | awk '{print "md5"$1}')" > /etc/pgpool2/pool_passwd
    echo "${REPMGR_USER}:$(echo -n "${REPMGR_PASSWORD}${REPMGR_USER}" | md5sum | awk '{print "md5"$1}')" >> /etc/pgpool2/pool_passwd
    chmod 644 /etc/pgpool2/pool_passwd
    log "Generated pool_passwd"
}

# Generate pcp.conf
generate_pcp_conf() {
    echo "admin:$(pg_md5 L0ngS3cur3P@ssw0rd)" > /etc/pgpool2/pcp.conf
    chmod 644 /etc/pgpool2/pcp.conf
    log "Generated pcp.conf"
}

# Discover primary node
discover_primary() {
    log "Discovering primary node..."
    local nodes=(${PG_NODES//,/ })
    
    for node in "${nodes[@]}"; do
        local host="${node%:*}"
        local port="${node#*:}"
        [ "$host" = "$port" ] && port=5432
        
        if timeout 5 pg_isready -h "$host" -p "$port" >/dev/null 2>&1; then
            local is_primary=$(timeout 5 psql -h "$host" -p "$port" -U "$REPMGR_USER" -d postgres -tAc "SELECT NOT pg_is_in_recovery();" 2>/dev/null || echo "f")
            
            if [ "$is_primary" = "t" ]; then
                log "  → Primary found: $host:$port"
                return 0
            fi
        fi
    done
    
    log "  → No primary found yet, will retry"
    return 1
}

# Wait for at least one node to be available
wait_for_nodes() {
    log "Waiting for PostgreSQL nodes to be available..."
    local retries=30
    
    for i in $(seq 1 $retries); do
        if discover_primary; then
            return 0
        fi
        log "Retry $i/$retries..."
        sleep 5
    done
    
    log "[WARNING] No primary found after $retries retries, starting anyway"
    return 0
}

# Main
log "Starting pgpool-II for PostgreSQL cluster"

# Generate configs
generate_pgpool_conf
generate_pool_passwd
generate_pcp_conf

# Wait for nodes
wait_for_nodes

# Start pgpool
log "Starting pgpool-II..."
exec /usr/sbin/pgpool -n -f /etc/pgpool2/pgpool.conf -F /etc/pgpool2/pcp.conf
