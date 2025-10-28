#!/bin/bash

# ============================================================================
# Quick Start Script - LGTM+ Monitoring Stack
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "============================================================================"
echo "🚀 LGTM+ Monitoring Stack - Quick Start"
echo "============================================================================"
echo ""

# Check prerequisites
echo "[1/6] Checking prerequisites..."
if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found. Please install Docker first."
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose not found. Please install Docker Compose first."
    exit 1
fi

echo "✅ Docker $(docker --version)"
echo "✅ Docker Compose $(docker-compose --version)"
echo ""

# Check if .env exists
echo "[2/6] Checking environment configuration..."
if [ ! -f .env ]; then
    echo "⚠️  .env not found. Generating..."
    
    # Generate passwords
    POSTGRES_PASSWORD=$(openssl rand -base64 32)
    PROXYSQL_ADMIN_PASSWORD=$(openssl rand -base64 32)
    GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 32)
    POSTGRES_APP_READONLY_PASSWORD=$(openssl rand -base64 32)
    
    # Create .env
    cat > .env <<EOF
# Auto-generated on $(date)
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
PROXYSQL_ADMIN_PASSWORD=${PROXYSQL_ADMIN_PASSWORD}
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
POSTGRES_APP_READONLY_PASSWORD=${POSTGRES_APP_READONLY_PASSWORD}

# Email settings (update these)
SMTP_HOST=smtp.gmail.com:587
SMTP_FROM=alertmanager@pgcluster.local
SMTP_USER=your-email@gmail.com
SMTP_PASSWORD=your-app-password

# Slack settings (update these)
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
EOF
    
    echo "✅ Generated .env with secure passwords"
    echo ""
    echo "📝 IMPORTANT: Save these credentials!"
    echo "   Grafana admin password: ${GRAFANA_ADMIN_PASSWORD}"
    echo ""
    echo "⚠️  Update .env with your SMTP and Slack settings for alerts"
    echo ""
else
    echo "✅ .env file exists"
    echo ""
fi

# Create necessary directories
echo "[3/6] Creating directories..."
mkdir -p config/alerts
mkdir -p config/grafana/provisioning/datasources
mkdir -p config/grafana/provisioning/dashboards
mkdir -p config/grafana/dashboards/postgresql
mkdir -p config/grafana/dashboards/proxysql
mkdir -p config/grafana/dashboards/infrastructure
mkdir -p config/grafana/dashboards/monitoring
echo "✅ Directories created"
echo ""

# Check Docker network
echo "[4/6] Checking Docker network..."
if docker network inspect pg_cluster &> /dev/null; then
    echo "✅ pg_cluster network exists"
else
    echo "⚠️  pg_cluster network not found"
    echo "   Creating network for local testing..."
    docker network create pg_cluster
    echo "✅ Network created (use 'external: true' in docker-compose.yml if connecting to existing cluster)"
fi
echo ""

# Pull Docker images
echo "[5/6] Pulling Docker images..."
docker-compose pull
echo "✅ Images pulled"
echo ""

# Start stack
echo "[6/6] Starting monitoring stack..."
docker-compose up -d
echo ""

# Wait for services to be healthy
echo "⏳ Waiting for services to start..."
sleep 10

# Check service status
echo ""
echo "============================================================================"
echo "📊 Service Status"
echo "============================================================================"
docker-compose ps
echo ""

# Display access information
echo "============================================================================"
echo "🎉 Monitoring Stack Started Successfully!"
echo "============================================================================"
echo ""
echo "🌐 Access URLs:"
echo "   Grafana:       http://localhost:3000"
echo "   Prometheus:    http://localhost:9090"
echo "   Alertmanager:  http://localhost:9093"
echo "   Mimir:         http://localhost:9009"
echo "   Loki:          http://localhost:3100"
echo "   Tempo:         http://localhost:3200"
echo ""
echo "🔑 Grafana Credentials:"
echo "   Username: admin"
echo "   Password: (check .env file or output above)"
echo ""
echo "📈 Next Steps:"
echo "   1. Open Grafana at http://localhost:3000"
echo "   2. Import dashboards:"
echo "      - PostgreSQL: Dashboard ID 9628"
echo "      - Node Exporter: Dashboard ID 1860"
echo "      - ProxySQL: Dashboard ID 12859"
echo "   3. Configure alert channels in Alertmanager"
echo "   4. Review logs: docker-compose logs -f"
echo ""
echo "📚 Documentation: ./README.md"
echo ""
echo "============================================================================"

# Show Grafana password
if [ -f .env ]; then
    GRAFANA_PASS=$(grep GRAFANA_ADMIN_PASSWORD .env | cut -d'=' -f2)
    echo "🔐 Grafana Password: ${GRAFANA_PASS}"
    echo "============================================================================"
fi
