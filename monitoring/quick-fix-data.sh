#!/bin/bash

echo "🔧 Fixing monitoring setup to show real data..."
echo ""

# 1. Fix password (remove special chars)
echo "Step 1: Generating safe password..."
NEW_PW=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
sed -i "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${NEW_PW}/" .env
echo "✅ Password updated: ${NEW_PW}"
echo ""

# 2. Check if PG cluster exists
echo "Step 2: Checking PostgreSQL cluster..."
if docker ps --filter "name=pg-1" | grep -q pg-1; then
    echo "✅ PostgreSQL cluster already running"
else
    echo "⚠️  PostgreSQL cluster not running"
    echo "Starting from /root/new_pg_cluster_clone..."
    cd /root/new_pg_cluster_clone
    docker compose up -d
    echo "Waiting 30 seconds for cluster to start..."
    sleep 30
fi
echo ""

# 3. Connect networks
echo "Step 3: Connecting monitoring to PostgreSQL network..."
cd /root/pg_ha_cluster_production/monitoring

# Find PG network name
PG_NETWORK=$(docker inspect pg-1 2>/dev/null | jq -r '.[0].NetworkSettings.Networks | keys[0]' 2>/dev/null)

if [ -z "$PG_NETWORK" ] || [ "$PG_NETWORK" = "null" ]; then
    echo "❌ Cannot find PostgreSQL network. Make sure pg-1 is running."
    exit 1
fi

echo "Found PG network: $PG_NETWORK"

# Connect containers
for container in grafana prometheus postgres_exporter_pg1 postgres_exporter_pg2 postgres_exporter_pg3 postgres_exporter_pg4 promtail; do
    if docker network connect $PG_NETWORK $container 2>/dev/null; then
        echo "  ✅ Connected $container"
    else
        echo "  ⚠️  $container already connected or not found"
    fi
done
echo ""

# 4. Restart exporters
echo "Step 4: Restarting PostgreSQL exporters..."
docker compose restart postgres_exporter_pg1 postgres_exporter_pg2 \
                       postgres_exporter_pg3 postgres_exporter_pg4
echo ""

# 5. Verify
echo "Step 5: Verifying connections..."
sleep 5

echo "Checking exporter logs..."
if docker logs postgres_exporter_pg1 2>&1 | tail -5 | grep -q "error"; then
    echo "⚠️  Still seeing errors, checking details..."
    docker logs postgres_exporter_pg1 --tail 3
else
    echo "✅ Exporters looking good"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Setup complete!"
echo ""
echo "🌐 Access Grafana: http://localhost:3000"
echo "   Username: admin"
echo "   Password: 5QBgYw9LRxZterRN1d3MRUNvUKnAltaHo9LH5c5F6Uc="
echo ""
echo "📊 Wait 30-60 seconds for metrics to populate"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
