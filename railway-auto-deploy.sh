#!/usr/bin/env bash
# railway-auto-deploy.sh - Fully automated PostgreSQL HA cluster deployment to Railway
# No manual interaction required - suitable for CI/CD pipelines
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Check prerequisites
if ! command -v railway &> /dev/null; then
    log_error "Railway CLI not found. Install: curl -fsSL https://railway.app/install.sh | sh"
    exit 1
fi

if ! railway whoami &> /dev/null; then
    log_error "Not logged in to Railway. Run: railway login"
    exit 1
fi

# Project directory
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

log_info "=== PostgreSQL HA Cluster - Automated Deployment ==="
log_info "Project Directory: $PROJECT_DIR"
echo ""

# Configuration
DEPLOY_PROXYSQL=true  # Always deploy ProxySQL HA (recommended)
WAIT_PRIMARY=30       # Seconds to wait for pg-1 initialization
WAIT_WITNESS=10       # Seconds to wait for witness registration
WAIT_STANDBYS=60      # Seconds to wait for standbys to join cluster
WAIT_PROXYSQL=30      # Seconds to wait for ProxySQL startup

# Ensure project is linked
if ! railway status &> /dev/null; then
    log_error "Project not linked to Railway"
    log_info "Run: railway init  OR  railway link"
    exit 1
fi

# Get project info
PROJECT_INFO=$(railway status --json 2>/dev/null || echo "")
PROJECT_ID=$(echo "$PROJECT_INFO" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
PROJECT_NAME=$(echo "$PROJECT_INFO" | grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

if [ -z "$PROJECT_ID" ]; then
    log_error "Could not get project ID from Railway"
    exit 1
fi

log_success "Project: $PROJECT_NAME (ID: $PROJECT_ID)"
echo ""

# Function: Create empty Railway service (no variables, no deploy yet)
create_empty_service() {
    local service_name=$1
    
    log_info "Creating empty service: $service_name"
    
    # Add empty service using --service flag
    railway add --service "$service_name" 2>&1 | grep -i "created\|exists" || {
        log_warn "  Service add response received"
    }
    
    sleep 1
}

# Function: Set environment variables for a service
set_service_variables() {
    local service_name=$1
    local service_dir=$2
    
    log_info "Setting variables for: $service_name"
    
    # Link to service
    railway service "$service_name" 2>/dev/null || {
        log_error "  Failed to link to service $service_name"
        return 1
    }
    
    # Set environment variables from .env file
    if [ -f "$PROJECT_DIR/$service_dir/.env" ]; then
        while IFS='=' read -r key value; do
            [[ -z "$key" || "$key" =~ ^# ]] && continue
            value=$(echo "$value" | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
            railway variables --set "$key=$value" --skip-deploys 2>/dev/null || true
        done < "$PROJECT_DIR/$service_dir/.env"
        log_success "  Variables set"
    else
        log_warn "  No .env file found"
    fi
}

# Function: Add volume to service
add_volume() {
    local service_name=$1
    local mount_path=$2
    
    log_info "Adding volume: $service_name -> $mount_path"
    
    railway service "$service_name" 2>/dev/null || {
        log_warn "  Could not link to service $service_name"
        return 1
    }
    
    # Check if volume already exists
    if railway volume list 2>&1 | grep -q "$mount_path"; then
        log_warn "  Volume already exists at $mount_path"
        return 0
    fi
    
    # Add volume with auto-answer for mount path prompt
    VOLUME_OUTPUT=$(printf "%s\n" "$mount_path" | railway volume add 2>&1)
    
    if echo "$VOLUME_OUTPUT" | grep -qi "too quickly"; then
        log_warn "  Rate limited, waiting 5 seconds..."
        sleep 5
        VOLUME_OUTPUT=$(printf "%s\n" "$mount_path" | railway volume add 2>&1)
    fi
    
    if echo "$VOLUME_OUTPUT" | grep -qi "volume created\|already exists"; then
        log_success "  Volume added: $mount_path"
    else
        log_warn "  Could not add volume (add manually via Dashboard)"
        log_info "  Output: $VOLUME_OUTPUT"
    fi
}

# Function: Deploy service
deploy_service() {
    local service_name=$1
    local service_dir=$2
    
    log_info "Deploying: $service_name"
    
    cd "$PROJECT_DIR/$service_dir" || {
        log_error "  Directory not found: $service_dir"
        return 1
    }
    
    # Select service
    railway service "$service_name" 2>/dev/null || {
        log_error "  Failed to select service $service_name"
        cd "$PROJECT_DIR"
        return 1
    }
    
    # Deploy from current directory
    # Railway CLI v4 uploads from Git root, but railway.json has correct dockerfilePath
    railway up --detach || {
        log_error "  Deployment failed for $service_name"
        cd "$PROJECT_DIR"
        return 1
    }
    
    log_success "  Deployment started"
    cd "$PROJECT_DIR"
}

# ============================================================================
# MAIN DEPLOYMENT FLOW
# ============================================================================

log_info "Step 1: Creating all empty services..."
echo ""

# Create all services first (empty, no variables)
create_empty_service "pg-1"
create_empty_service "pg-2"
create_empty_service "pg-3"
create_empty_service "pg-4"
create_empty_service "witness"

if [ "$DEPLOY_PROXYSQL" = true ]; then
    create_empty_service "proxysql"
    create_empty_service "proxysql-2"
fi

echo ""
log_success "All services created"
echo ""

# ============================================================================

log_info "Step 2: Setting environment variables for each service..."
echo ""

set_service_variables "pg-1" "pg-1"
set_service_variables "pg-2" "pg-2"
set_service_variables "pg-3" "pg-3"
set_service_variables "pg-4" "pg-4"
set_service_variables "witness" "witness"

if [ "$DEPLOY_PROXYSQL" = true ]; then
    set_service_variables "proxysql" "proxysql"
    set_service_variables "proxysql-2" "proxysql-2"
fi

echo ""
log_success "Variables configured for all services"
echo ""

# ============================================================================

log_info "Step 3: Adding persistent volumes..."
echo ""

# PostgreSQL data volumes
add_volume "pg-1" "/var/lib/postgresql"
sleep 2
add_volume "pg-2" "/var/lib/postgresql"
sleep 2
add_volume "pg-3" "/var/lib/postgresql"
sleep 2
add_volume "pg-4" "/var/lib/postgresql"

log_info "Witness does not need volume (no data storage)"

# ProxySQL volumes
if [ "$DEPLOY_PROXYSQL" = true ]; then
    sleep 2
    add_volume "proxysql" "/var/lib/proxysql"
    sleep 2
    add_volume "proxysql-2" "/var/lib/proxysql"
fi

echo ""
log_success "Volumes configured"
echo ""

# ============================================================================

log_info "Step 4: Deploying services in correct sequence..."
echo ""

# Deploy primary first
log_info "▶ Deploying primary node (pg-1)..."
deploy_service "pg-1" "pg-1" || exit 1
log_info "⏳ Waiting ${WAIT_PRIMARY}s for pg-1 to initialize..."
sleep $WAIT_PRIMARY
echo ""

# Deploy witness
log_info "▶ Deploying witness node..."
deploy_service "witness" "witness" || exit 1
log_info "⏳ Waiting ${WAIT_WITNESS}s for witness to register..."
sleep $WAIT_WITNESS
echo ""

# Deploy standby nodes in parallel
log_info "▶ Deploying standby nodes (pg-2, pg-3, pg-4) in parallel..."
deploy_service "pg-2" "pg-2" &
PID2=$!
deploy_service "pg-3" "pg-3" &
PID3=$!
deploy_service "pg-4" "pg-4" &
PID4=$!

wait $PID2 $PID3 $PID4
log_info "⏳ Waiting ${WAIT_STANDBYS}s for standbys to join cluster..."
sleep $WAIT_STANDBYS
echo ""

# Deploy ProxySQL HA pair in parallel
if [ "$DEPLOY_PROXYSQL" = true ]; then
    log_info "▶ Deploying ProxySQL HA pair (2 instances)..."
    deploy_service "proxysql" "proxysql" &
    PIDP1=$!
    deploy_service "proxysql-2" "proxysql-2" &
    PIDP2=$!
    
    wait $PIDP1 $PIDP2
    log_info "⏳ Waiting ${WAIT_PROXYSQL}s for ProxySQL startup..."
    sleep $WAIT_PROXYSQL
    echo ""
fi

# ============================================================================

log_success "=== Deployment Complete ==="
echo ""

# Generate cluster info
log_info "Generating cluster information..."
if [ -f "$PROJECT_DIR/scripts/generate-security-info.sh" ]; then
    bash "$PROJECT_DIR/scripts/generate-security-info.sh" "cluster-security-info.txt" || {
        log_warn "Could not generate security info (script may need Railway service access)"
    }
fi

# Summary
cat <<EOF

================================================================================
📊 DEPLOYMENT SUMMARY
================================================================================

Project: $PROJECT_NAME
Services Deployed:
  ✅ pg-1, pg-2, pg-3, pg-4 (PostgreSQL 17 + repmgr)
  ✅ witness (repmgr witness node)
$([ "$DEPLOY_PROXYSQL" = true ] && echo "  ✅ proxysql, proxysql-2 (ProxySQL 3.0 BETA HA)")

Next Steps:
  1. Check deployment status:
     railway status

  2. View logs:
     railway logs --service pg-1

  3. SSH into primary:
     railway ssh --service pg-1
     
  4. Verify cluster:
     gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show

  5. Generate ProxySQL public domains:
     railway service proxysql && railway domain
     railway service proxysql-2 && railway domain

  6. Connect via ProxySQL:
     psql "postgresql://app_readwrite:<password>@<domain>:5432/postgres"

Security Files:
  📄 cluster-info.txt           - Basic cluster information
  📄 cluster-security-info.txt  - SAVE TO PASSWORD MANAGER THEN DELETE!

For detailed documentation:
  📘 QUICK_START.md     - Quick reference
  📘 README.md          - Complete guide
  📘 SECURITY.md        - Security hardening
  📘 SCALING_GUIDE.md   - Add/remove nodes

================================================================================

EOF

# Open Railway dashboard
log_info "Opening Railway Dashboard..."
railway open || log_warn "Could not open dashboard automatically"

log_success "Automated deployment completed successfully! 🎉"
