#!/usr/bin/env bash
# Monitor ProxySQL health and log status

while true; do
    sleep 60
    
    # Check ProxySQL process
    if ! pgrep -x proxysql > /dev/null; then
        echo "[$(date -Iseconds)] [CRITICAL] ProxySQL process not running!"
        exit 1
    fi
    
    # Check admin interface (PostgreSQL admin port 6132)
    if ! timeout 3 nc -z 127.0.0.1 6132 >/dev/null 2>&1; then
        echo "[$(date -Iseconds)] [WARNING] ProxySQL admin interface not responding"
    fi
    
    # Log server stats using psql
    echo "[$(date -Iseconds)] [INFO] ProxySQL stats:"
    PGPASSWORD="admin" psql -h 127.0.0.1 -p 6132 -U admin -d proxysql -c "SELECT hostgroup_id,hostname,port,status,ConnUsed,MaxConnUsed FROM stats_pgsql_connection_pool;" 2>/dev/null || echo "Unable to fetch stats"
done
