#!/bin/bash

# ============================================================================
# Status Script - LGTM+ Monitoring Stack
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "============================================================================"
echo "📊 LGTM+ Monitoring Stack - Status"
echo "============================================================================"
echo ""

# Check if docker-compose.yml exists
if [ ! -f docker-compose.yml ]; then
    echo "❌ docker-compose.yml not found"
    exit 1
fi

echo "[1/5] Service Status"
echo "-------------------------------------------------------------------"
docker-compose ps
echo ""

echo "[2/5] Resource Usage"
echo "-------------------------------------------------------------------"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" \
    $(docker-compose ps -q 2>/dev/null)
echo ""

echo "[3/5] Volume Usage"
echo "-------------------------------------------------------------------"
docker volume ls --filter name=monitoring_ --format "table {{.Name}}\t{{.Driver}}"
echo ""
for vol in $(docker volume ls --filter name=monitoring_ -q); do
    size=$(docker run --rm -v $vol:/data alpine du -sh /data 2>/dev/null | awk '{print $1}')
    echo "$vol: $size"
done
echo ""

echo "[4/5] Network Connectivity"
echo "-------------------------------------------------------------------"
# Test Prometheus
if curl -s http://localhost:9090/-/healthy > /dev/null 2>&1; then
    echo "✅ Prometheus: http://localhost:9090 (healthy)"
else
    echo "❌ Prometheus: http://localhost:9090 (not responding)"
fi

# Test Grafana
if curl -s http://localhost:3000/api/health > /dev/null 2>&1; then
    echo "✅ Grafana: http://localhost:3000 (healthy)"
else
    echo "❌ Grafana: http://localhost:3000 (not responding)"
fi

# Test Loki
if curl -s http://localhost:3100/ready > /dev/null 2>&1; then
    echo "✅ Loki: http://localhost:3100 (ready)"
else
    echo "❌ Loki: http://localhost:3100 (not ready)"
fi

# Test Tempo
if curl -s http://localhost:3200/status > /dev/null 2>&1; then
    echo "✅ Tempo: http://localhost:3200 (ready)"
else
    echo "❌ Tempo: http://localhost:3200 (not ready)"
fi

# Test Mimir
if curl -s http://localhost:9009/ready > /dev/null 2>&1; then
    echo "✅ Mimir: http://localhost:9009 (ready)"
else
    echo "❌ Mimir: http://localhost:9009 (not ready)"
fi

# Test Alertmanager
if curl -s http://localhost:9093/-/healthy > /dev/null 2>&1; then
    echo "✅ Alertmanager: http://localhost:9093 (healthy)"
else
    echo "❌ Alertmanager: http://localhost:9093 (not responding)"
fi
echo ""

echo "[5/5] Prometheus Targets"
echo "-------------------------------------------------------------------"
if curl -s http://localhost:9090/-/healthy > /dev/null 2>&1; then
    curl -s http://localhost:9090/api/v1/targets | \
        jq -r '.data.activeTargets[] | "\(.labels.job)\t\(.labels.instance)\t\(.health)"' | \
        column -t -s $'\t' || echo "Install jq for better formatting"
else
    echo "❌ Prometheus not available"
fi
echo ""

echo "============================================================================"
echo "📚 Quick Commands"
echo "============================================================================"
echo "  View logs:           docker-compose logs -f [service]"
echo "  Restart service:     docker-compose restart [service]"
echo "  Stop stack:          ./stop.sh"
echo "  Remove all:          docker-compose down -v"
echo ""
echo "  Access Grafana:      http://localhost:3000"
echo "  Access Prometheus:   http://localhost:9090"
echo "============================================================================"
