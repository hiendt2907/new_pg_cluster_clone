#!/bin/bash
# Display cluster credentials and connection information

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Check if .env exists
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}❌ Error: .env file not found!${NC}"
    echo -e "${YELLOW}Run this first: ${BLUE}./scripts/generate-passwords.sh${NC}"
    exit 1
fi

# Load environment variables
source "$ENV_FILE"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         PostgreSQL HA Cluster - Connection Information                  ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# System Status
echo -e "${BOLD}${CYAN}📊 SYSTEM STATUS${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Check if containers are running
if command -v docker &> /dev/null; then
    PGPOOL1_STATUS=$(docker ps --filter "name=pgpool-1" --format "{{.Status}}" 2>/dev/null || echo "Not running")
    PG1_STATUS=$(docker ps --filter "name=pg-1" --format "{{.Status}}" 2>/dev/null || echo "Not running")
    
    if [[ $PGPOOL1_STATUS == *"Up"* ]]; then
        echo -e "  Pgpool-1:     ${GREEN}✅ Running${NC} ($PGPOOL1_STATUS)"
    else
        echo -e "  Pgpool-1:     ${RED}❌ Stopped${NC}"
    fi
    
    if [[ $PG1_STATUS == *"Up"* ]]; then
        echo -e "  PostgreSQL:   ${GREEN}✅ Running${NC} ($PG1_STATUS)"
    else
        echo -e "  PostgreSQL:   ${RED}❌ Stopped${NC}"
    fi
else
    echo -e "  ${YELLOW}⚠️  Docker not available - cannot check container status${NC}"
fi

echo ""

# Database Credentials
echo -e "${BOLD}${CYAN}🔐 DATABASE CREDENTIALS${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${BOLD}Superuser (postgres):${NC}"
echo -e "    Username: ${GREEN}postgres${NC}"
echo -e "    Password: ${YELLOW}${POSTGRES_PASSWORD}${NC}"
echo ""
echo -e "  ${BOLD}Replication User (repmgr):${NC}"
echo -e "    Username: ${GREEN}repmgr${NC}"
echo -e "    Password: ${YELLOW}${REPMGR_PASSWORD}${NC}"
echo ""
echo -e "  ${BOLD}Application User (Read/Write):${NC}"
echo -e "    Username: ${GREEN}app_readwrite${NC}"
echo -e "    Password: ${YELLOW}${APP_READWRITE_PASSWORD}${NC}"
echo ""
echo -e "  ${BOLD}Application User (Read-Only):${NC}"
echo -e "    Username: ${GREEN}app_readonly${NC}"
echo -e "    Password: ${YELLOW}${APP_READONLY_PASSWORD}${NC}"
echo ""

# Pgpool Credentials
echo -e "${BOLD}${CYAN}🔧 PGPOOL ADMIN${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  PCP Admin:"
echo -e "    Username: ${GREEN}postgres${NC}"
echo -e "    Password: ${YELLOW}${PCP_PASSWORD}${NC}"
echo ""

# Connection Endpoints
echo -e "${BOLD}${CYAN}🔌 CONNECTION ENDPOINTS${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${BOLD}Pgpool (Primary):${NC}"
echo -e "    Host: ${GREEN}localhost${NC}"
echo -e "    Port: ${GREEN}${PGPOOL_PORT:-15432}${NC}"
echo ""
echo -e "  ${BOLD}Pgpool (Backup):${NC}"
echo -e "    Host: ${GREEN}localhost${NC}"
echo -e "    Port: ${GREEN}${PGPOOL2_PORT:-15433}${NC}"
echo ""

# PSQL Commands
echo -e "${BOLD}${CYAN}💻 PSQL CONNECTION COMMANDS${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${BOLD}Connect as superuser:${NC}"
echo -e "    ${CYAN}PGPASSWORD='${POSTGRES_PASSWORD}' psql -h localhost -p ${PGPOOL_PORT:-15432} -U postgres -d postgres${NC}"
echo ""
echo -e "  ${BOLD}Connect as app_readwrite:${NC}"
echo -e "    ${CYAN}PGPASSWORD='${APP_READWRITE_PASSWORD}' psql -h localhost -p ${PGPOOL_PORT:-15432} -U app_readwrite -d postgres${NC}"
echo ""
echo -e "  ${BOLD}Connect as app_readonly:${NC}"
echo -e "    ${CYAN}PGPASSWORD='${APP_READONLY_PASSWORD}' psql -h localhost -p ${PGPOOL_PORT:-15432} -U app_readonly -d postgres${NC}"
echo ""

# Application Connection Strings
echo -e "${BOLD}${CYAN}🔗 APPLICATION CONNECTION STRINGS${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${BOLD}PostgreSQL URI (Read/Write):${NC}"
echo -e "    ${CYAN}postgresql://app_readwrite:${APP_READWRITE_PASSWORD}@localhost:${PGPOOL_PORT:-15432}/postgres${NC}"
echo ""
echo -e "  ${BOLD}PostgreSQL URI (Read-Only):${NC}"
echo -e "    ${CYAN}postgresql://app_readonly:${APP_READONLY_PASSWORD}@localhost:${PGPOOL_PORT:-15432}/postgres${NC}"
echo ""

# Node.js Example
echo -e "${BOLD}${CYAN}📝 NODE.JS EXAMPLE${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
cat << 'NODEJS'
  const { Pool } = require('pg');
  
  const pool = new Pool({
    host: 'localhost',
NODEJS
echo -e "    port: ${PGPOOL_PORT:-15432},"
echo -e "    user: 'app_readwrite',"
echo -e "    password: '${APP_READWRITE_PASSWORD}',"
cat << 'NODEJS'
    database: 'postgres',
    max: 20,
  });
NODEJS
echo ""

# Python Example
echo -e "${BOLD}${CYAN}🐍 PYTHON EXAMPLE${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
cat << 'PYTHON'
  import psycopg2
  
  conn = psycopg2.connect(
    host="localhost",
PYTHON
echo -e "    port=${PGPOOL_PORT:-15432},"
echo -e "    user=\"app_readwrite\","
echo -e "    password=\"${APP_READWRITE_PASSWORD}\","
cat << 'PYTHON'
    database="postgres"
  )
PYTHON
echo ""

# Monitoring Dashboards
echo -e "${BOLD}${CYAN}📊 MONITORING DASHBOARDS${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Grafana:       ${CYAN}http://localhost:${GRAFANA_PORT:-3001}${NC}"
echo -e "                 ${YELLOW}User: admin / Pass: admin${NC}"
echo ""
echo -e "  Prometheus:    ${CYAN}http://localhost:${PROMETHEUS_PORT:-9090}${NC}"
echo -e "  AlertManager:  ${CYAN}http://localhost:${ALERTMANAGER_PORT:-9093}${NC}"
echo ""

# Security Warning
echo -e "${BOLD}${RED}⚠️  SECURITY WARNING${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${YELLOW}• Keep .env file secure - DO NOT commit to Git!${NC}"
echo -e "  ${YELLOW}• Change default Grafana password on first login${NC}"
echo -e "  ${YELLOW}• Use SSL/TLS connections in production${NC}"
echo -e "  ${YELLOW}• Restrict network access with firewall rules${NC}"
echo ""

# Quick Commands
echo -e "${BOLD}${CYAN}🚀 QUICK COMMANDS${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Check cluster status:"
echo -e "    ${CYAN}docker exec pg-1 gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show${NC}"
echo ""
echo -e "  Check pgpool nodes:"
echo -e "    ${CYAN}docker exec pgpool-1 psql -h localhost -p 5432 -U postgres -c \"SHOW POOL_NODES;\"${NC}"
echo ""
echo -e "  View pgpool logs:"
echo -e "    ${CYAN}docker logs -f pgpool-1${NC}"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════${NC}"
echo ""
