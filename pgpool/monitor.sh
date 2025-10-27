#!/usr/bin/env bash
# Monitor pgpool-II health and backend status

while true; do
    sleep 60
    
    # Check pgpool process
    if ! pgrep -x pgpool > /dev/null; then
        echo "[$(date -Iseconds)] [CRITICAL] pgpool process not running!"
        exit 1
    fi
    
    # Show backend node status
    echo "[$(date -Iseconds)] [INFO] Backend status:"
    pcp_node_info -h localhost -p 9898 -U admin -w 2>/dev/null || echo "Unable to fetch backend info"
    
    # Show pool status
    echo "[$(date -Iseconds)] [INFO] Pool status:"
    pcp_pool_status -h localhost -p 9898 -U admin -w 2>/dev/null | head -20 || echo "Unable to fetch pool status"
done
