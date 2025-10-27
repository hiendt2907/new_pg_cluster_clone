#!/usr/bin/env bash
# railway-setup-shared-vars.sh - Tạo shared variables cho cluster
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $*"; }

log_info "Setting up shared variables for PostgreSQL HA Cluster..."
echo ""

# Generate secure passwords if not provided
if [ -z "${POSTGRES_PASSWORD:-}" ]; then
    log_info "Generating secure POSTGRES_PASSWORD..."
    POSTGRES_PASSWORD=$(openssl rand -base64 32)
    log_success "Generated: ${POSTGRES_PASSWORD:0:8}... (32 characters)"
else
    log_info "Using provided POSTGRES_PASSWORD"
fi

if [ -z "${REPMGR_PASSWORD:-}" ]; then
    log_info "Generating secure REPMGR_PASSWORD..."
    REPMGR_PASSWORD=$(openssl rand -base64 32)
    log_success "Generated: ${REPMGR_PASSWORD:0:8}... (32 characters)"
else
    log_info "Using provided REPMGR_PASSWORD"
fi

if [ -z "${APP_READONLY_PASSWORD:-}" ]; then
    log_info "Generating secure APP_READONLY_PASSWORD..."
    APP_READONLY_PASSWORD=$(openssl rand -base64 32)
    log_success "Generated: ${APP_READONLY_PASSWORD:0:8}... (32 characters)"
else
    log_info "Using provided APP_READONLY_PASSWORD"
fi

if [ -z "${APP_READWRITE_PASSWORD:-}" ]; then
    log_info "Generating secure APP_READWRITE_PASSWORD..."
    APP_READWRITE_PASSWORD=$(openssl rand -base64 32)
    log_success "Generated: ${APP_READWRITE_PASSWORD:0:8}... (32 characters)"
else
    log_info "Using provided APP_READWRITE_PASSWORD"
fi

if [ -z "${PROXYSQL_ADMIN_PASSWORD:-}" ]; then
    log_info "Generating secure PROXYSQL_ADMIN_PASSWORD..."
    PROXYSQL_ADMIN_PASSWORD=$(openssl rand -base64 32)
    log_success "Generated: ${PROXYSQL_ADMIN_PASSWORD:0:8}... (32 characters)"
else
    log_info "Using provided PROXYSQL_ADMIN_PASSWORD"
fi

echo ""
log_warn "⚠️  IMPORTANT: Save these passwords securely!"
log_warn "   POSTGRES_PASSWORD:       $POSTGRES_PASSWORD"
log_warn "   REPMGR_PASSWORD:         $REPMGR_PASSWORD"
log_warn "   APP_READONLY_PASSWORD:   $APP_READONLY_PASSWORD"
log_warn "   APP_READWRITE_PASSWORD:  $APP_READWRITE_PASSWORD"
log_warn "   PROXYSQL_ADMIN_PASSWORD: $PROXYSQL_ADMIN_PASSWORD"
echo ""

# Set shared variables in Railway
log_info "Setting Railway environment variables..."

railway variables --set "POSTGRES_PASSWORD=$POSTGRES_PASSWORD"
railway variables --set "REPMGR_PASSWORD=$REPMGR_PASSWORD"
railway variables --set "APP_READONLY_PASSWORD=$APP_READONLY_PASSWORD"
railway variables --set "APP_READWRITE_PASSWORD=$APP_READWRITE_PASSWORD"
railway variables --set "PROXYSQL_ADMIN_PASSWORD=$PROXYSQL_ADMIN_PASSWORD"
railway variables --set "PRIMARY_HINT=pg-1"

log_success "Shared variables set successfully!"
log_info "These variables are now available to all services in this environment."
