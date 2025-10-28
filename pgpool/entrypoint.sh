#!/bin/bash
set -e

echo "[$(date)] Pgpool-II Entrypoint - Starting..."

# Environment variables with defaults
PGPOOL_NODE_ID=${PGPOOL_NODE_ID:-1}
PGPOOL_HOSTNAME=${PGPOOL_HOSTNAME:-pgpool-1}
OTHER_PGPOOL_HOSTNAME=${OTHER_PGPOOL_HOSTNAME:-pgpool-2}
OTHER_PGPOOL_PORT=${OTHER_PGPOOL_PORT:-9999}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:?ERROR: POSTGRES_PASSWORD not set}
REPMGR_PASSWORD=${REPMGR_PASSWORD:?ERROR: REPMGR_PASSWORD not set}
APP_READONLY_PASSWORD=${APP_READONLY_PASSWORD:?ERROR: APP_READONLY_PASSWORD not set}
APP_READWRITE_PASSWORD=${APP_READWRITE_PASSWORD:?ERROR: APP_READWRITE_PASSWORD not set}

# Create necessary directories
mkdir -p /var/run/pgpool /var/log/pgpool
chown -R postgres:postgres /var/run/pgpool /var/log/pgpool

# Copy configuration files to /etc/pgpool-II if not already there
if [ ! -f /etc/pgpool-II/pgpool.conf ]; then
    echo "[$(date)] Copying configuration files..."
    cp /config/pgpool.conf /etc/pgpool-II/pgpool.conf
    cp /config/pool_hba.conf /etc/pgpool-II/pool_hba.conf
    cp /config/pcp.conf /etc/pgpool-II/pcp.conf
fi

# Create pgpool_node_id file (required for watchdog)
echo "$PGPOOL_NODE_ID" > /etc/pgpool-II/pgpool_node_id
chmod 644 /etc/pgpool-II/pgpool_node_id
echo "[$(date)] Created pgpool_node_id file with ID: $PGPOOL_NODE_ID"

# Update pgpool.conf with runtime values
echo "[$(date)] Configuring pgpool.conf with runtime values..."

# Set watchdog hostname and priority based on node ID
sed -i "s/^wd_hostname0 = .*/wd_hostname0 = '${PGPOOL_HOSTNAME}'/" /etc/pgpool-II/pgpool.conf
sed -i "s/^wd_priority0 = .*/wd_priority0 = ${PGPOOL_NODE_ID}/" /etc/pgpool-II/pgpool.conf
sed -i "s/^heartbeat_hostname0 = .*/heartbeat_hostname0 = '${PGPOOL_HOSTNAME}'/" /etc/pgpool-II/pgpool.conf

# Configure other pgpool node for watchdog
sed -i "s/^other_pgpool_hostname0 = .*/other_pgpool_hostname0 = '${OTHER_PGPOOL_HOSTNAME}'/" /etc/pgpool-II/pgpool.conf
sed -i "s/^other_pgpool_port0 = .*/other_pgpool_port0 = ${OTHER_PGPOOL_PORT}/" /etc/pgpool-II/pgpool.conf

# Update passwords in pgpool.conf
sed -i "s/^sr_check_password = .*/sr_check_password = '${REPMGR_PASSWORD}'/" /etc/pgpool-II/pgpool.conf
sed -i "s/^health_check_password = .*/health_check_password = '${REPMGR_PASSWORD}'/" /etc/pgpool-II/pgpool.conf
sed -i "s/^wd_lifecheck_password = .*/wd_lifecheck_password = '${REPMGR_PASSWORD}'/" /etc/pgpool-II/pgpool.conf

# Wait for primary PostgreSQL to be ready
echo "[$(date)] Waiting for pg-1 (primary) to be ready..."
until PGPASSWORD=$POSTGRES_PASSWORD psql -h pg-1 -U postgres -d postgres -c "SELECT 1" > /dev/null 2>&1; do
  echo "  Waiting for pg-1..."
  sleep 2
done
echo "  ✓ pg-1 is ready!"

# Create pool_passwd file with user credentials
# For SCRAM-SHA-256, pgpool needs to query backend, so we use text format
echo "[$(date)] Creating pool_passwd with text format for SCRAM-SHA-256..."

# Create pool_passwd in text format (username:password)
# Pgpool will handle SCRAM authentication with backends
cat > /etc/pgpool-II/pool_passwd <<EOF
postgres:$POSTGRES_PASSWORD
repmgr:$REPMGR_PASSWORD
app_readonly:$APP_READONLY_PASSWORD
app_readwrite:$APP_READWRITE_PASSWORD
pgpool:$REPMGR_PASSWORD
EOF

chmod 600 /etc/pgpool-II/pool_passwd
echo "[$(date)] pool_passwd created with $(wc -l < /etc/pgpool-II/pool_passwd) users"

# Set correct permissions
chown postgres:postgres /etc/pgpool-II/*
chmod 600 /etc/pgpool-II/pool_passwd
chmod 600 /etc/pgpool-II/pcp.conf

# Create pgpool user in PostgreSQL if not exists
echo "[$(date)] Creating pgpool user in PostgreSQL..."
PGPASSWORD=$POSTGRES_PASSWORD psql -h pg-1 -U postgres -d postgres <<-EOSQL 2>/dev/null || true
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'pgpool') THEN
            CREATE USER pgpool WITH PASSWORD '${REPMGR_PASSWORD}';
        END IF;
    END
    \$\$;
    
    GRANT pg_monitor TO pgpool;
    GRANT CONNECT ON DATABASE postgres TO pgpool;
EOSQL

echo "[$(date)] Pgpool user created/verified"

# Test backend connections
echo "[$(date)] Testing backend connections..."
for backend in pg-1 pg-2 pg-3 pg-4; do
    if PGPASSWORD=$REPMGR_PASSWORD psql -h $backend -U repmgr -d postgres -c "SELECT 1" > /dev/null 2>&1; then
        echo "  ✓ $backend is reachable"
    else
        echo "  ✗ $backend is NOT reachable (may come online later)"
    fi
done

# Display configuration summary
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║          Pgpool-II Configuration Summary                ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Pgpool Node ID: $PGPOOL_NODE_ID"
echo "  Pgpool Hostname: $PGPOOL_HOSTNAME"
echo "  Watchdog Priority: $PGPOOL_NODE_ID"
echo "  Other Pgpool: ${OTHER_PGPOOL_HOSTNAME}:${OTHER_PGPOOL_PORT}"
echo ""
echo "  Backend Configuration:"
echo "    pg-1 (Primary):  weight=0 (writes only)"
echo "    pg-2 (Standby):  weight=1 (reads)"
echo "    pg-3 (Standby):  weight=1 (reads)"
echo "    pg-4 (Standby):  weight=1 (reads)"
echo ""
echo "  Features:"
echo "    ✓ Load Balancing: ON (statement-level)"
echo "    ✓ Streaming Replication Check: ON"
echo "    ✓ Health Check: ON (every 10s)"
echo "    ✓ Watchdog: ON (pgpool HA)"
echo "    ✓ Connection Pooling: ON"
echo ""
echo "  Ports:"
echo "    PostgreSQL: 5432"
echo "    PCP: 9898"
echo "    Watchdog: 9000"
echo "    Heartbeat: 9694"
echo ""
echo "══════════════════════════════════════════════════════════"
echo ""

# Start monitoring script in background if exists
if [ -f /usr/local/bin/monitor.sh ]; then
    echo "[$(date)] Starting monitoring script..."
    /usr/local/bin/monitor.sh &
fi

# Start pgpool-II
echo "[$(date)] Starting pgpool-II..."
exec gosu postgres pgpool -n -f /etc/pgpool-II/pgpool.conf -F /etc/pgpool-II/pcp.conf -a /etc/pgpool-II/pool_hba.conf
