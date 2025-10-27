#!/usr/bin/env bash
# railway-setup-shared-vars.sh - Tạo shared variables cho cluster
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }

log_info "Setting up shared variables for PostgreSQL HA Cluster..."

# Shared variables cho tất cả PostgreSQL nodes
log_info "Setting POSTGRES_PASSWORD..."
railway variables --set "POSTGRES_PASSWORD=L0ngS3cur3P@ssw0rd"

log_info "Setting REPMGR_PASSWORD..."
railway variables --set "REPMGR_PASSWORD=L0ngS3cur3P@ssw0rd"

log_info "Setting PRIMARY_HINT..."
railway variables --set "PRIMARY_HINT=pg-1"

log_success "Shared variables set successfully!"
log_info "These variables are now available to all services in this environment."
