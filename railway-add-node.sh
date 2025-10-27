#!/usr/bin/env bash
# railway-add-node.sh - Tự động thêm PostgreSQL node mới vào cluster
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

# Check Railway CLI
if ! command -v railway &> /dev/null; then
    log_error "Railway CLI not found. Install: curl -fsSL https://railway.app/install.sh | sh"
    exit 1
fi

if ! railway whoami &> /dev/null; then
    log_error "Not logged in to Railway. Run: railway login"
    exit 1
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# Get node number from user
if [ -z "${1:-}" ]; then
    log_error "Usage: $0 <node_number>"
    log_info "Example: $0 5     # Creates pg-5"
    log_info "Example: $0 6     # Creates pg-6"
    exit 1
fi

NODE_NUM=$1
NODE_NAME="pg-${NODE_NUM}"
NODE_DIR="$PROJECT_DIR/$NODE_NAME"

# Validate node number
if ! [[ "$NODE_NUM" =~ ^[0-9]+$ ]]; then
    log_error "Node number must be a number. Got: '$NODE_NUM'"
    exit 1
fi

if [ "$NODE_NUM" -lt 5 ]; then
    log_error "Node number must be >= 5 (pg-1 to pg-4 already exist)"
    exit 1
fi

# Check if node already exists
if [ -d "$NODE_DIR" ]; then
    log_error "Node directory already exists: $NODE_DIR"
    log_info "To redeploy, delete the directory first: rm -rf $NODE_DIR"
    exit 1
fi

log_info "=== Adding PostgreSQL Node: $NODE_NAME ==="

# Step 1: Copy from pg-4 (template)
log_info "Step 1: Creating node directory from pg-4 template..."
cp -r "$PROJECT_DIR/pg-4" "$NODE_DIR"
log_success "Directory created: $NODE_DIR"

# Step 2: Update .env file
log_info "Step 2: Updating .env configuration..."
cat > "$NODE_DIR/.env" <<EOF
# Node identification
NODE_NAME=$NODE_NAME
NODE_ID=$NODE_NUM

# Peer nodes (for discovery)
PEERS=pg-1.railway.internal,pg-2.railway.internal,pg-3.railway.internal

# Passwords (Railway environment variables)
POSTGRES_PASSWORD=\${{POSTGRES_PASSWORD}}
REPMGR_PASSWORD=\${{REPMGR_PASSWORD}}

# Primary hint (bootstrap node)
PRIMARY_HINT=\${{PRIMARY_HINT}}

# PostgreSQL settings
POSTGRES_USER=postgres
REPMGR_USER=repmgr
REPMGR_DB=repmgr
PG_PORT=5432
EOF
log_success ".env file configured for $NODE_NAME (ID: $NODE_NUM)"

# Step 3: Create Railway service
log_info "Step 3: Creating Railway service '$NODE_NAME'..."
cd "$NODE_DIR"

ADD_OUTPUT=$(railway add --service "$NODE_NAME" 2>&1 || true)
if echo "$ADD_OUTPUT" | grep -qi "already exists"; then
    log_warn "Service '$NODE_NAME' already exists on Railway"
elif echo "$ADD_OUTPUT" | grep -qi "created"; then
    log_success "Service '$NODE_NAME' created on Railway"
else
    log_info "Railway add output: $ADD_OUTPUT"
fi

sleep 2

# Step 4: Link to service
log_info "Step 4: Linking to service '$NODE_NAME'..."
if railway service "$NODE_NAME" 2>/dev/null; then
    log_success "Linked to service $NODE_NAME"
else
    log_error "Failed to link to service $NODE_NAME"
    log_info "Try manually: cd $NODE_DIR && railway service $NODE_NAME"
    exit 1
fi

# Step 5: Set environment variables
log_info "Step 5: Setting environment variables..."
while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^# ]] && continue
    value=$(echo "$value" | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
    log_info "  Setting $key"
    railway variables --set "$key=$value" --skip-deploys || {
        log_warn "  Failed to set $key, continuing..."
    }
done < .env
log_success "Environment variables set"

# Step 6: Add volume
log_info "Step 6: Adding persistent volume at /var/lib/postgresql..."
EXISTING_VOLUMES=$(railway volume list 2>&1 || echo "")
if echo "$EXISTING_VOLUMES" | grep -q "/var/lib/postgresql"; then
    log_warn "Volume already exists for $NODE_NAME"
else
    echo "/var/lib/postgresql" | railway volume add || {
        log_warn "Failed to add volume, may need manual setup via Railway Dashboard"
    }
    log_success "Volume added to $NODE_NAME"
fi

# Step 7: Deploy
log_info "Step 7: Deploying $NODE_NAME to Railway..."
railway up --detach || {
    log_error "Deployment failed for $NODE_NAME"
    log_info "Check logs: railway logs --service $NODE_NAME"
    exit 1
}
log_success "Deployment started for $NODE_NAME"

# Step 8: Update ProxySQL to include new node (no restart needed)
cd "$PROJECT_DIR"
log_info ""
log_info "Step 8: Adding $NODE_NAME to ProxySQL instances (no restart required)..."
log_info "Waiting 30 seconds for $NODE_NAME to be ready..."
sleep 30

# Add to ProxySQL instance 1
log_info "  Adding to proxysql instance 1..."
railway service proxysql
railway run bash -c "PGPASSWORD=admin psql -h 127.0.0.1 -p 6132 -U admin -d proxysql -c \"INSERT INTO pgsql_servers(hostgroup_id,hostname,port,weight,max_connections) VALUES (2,'${NODE_NAME}.railway.internal',5432,1000,100) ON CONFLICT DO NOTHING; LOAD PGSQL SERVERS TO RUNTIME; SAVE PGSQL SERVERS TO DISK;\"" 2>/dev/null && {
    log_success "  Added to proxysql instance 1"
} || {
    log_warn "  Failed to add to proxysql instance 1 (check if already exists or add manually)"
}

# Add to ProxySQL instance 2
log_info "  Adding to proxysql-2 instance 2..."
railway service proxysql-2
railway run bash -c "PGPASSWORD=admin psql -h 127.0.0.1 -p 6132 -U admin -d proxysql -c \"INSERT INTO pgsql_servers(hostgroup_id,hostname,port,weight,max_connections) VALUES (2,'${NODE_NAME}.railway.internal',5432,1000,100) ON CONFLICT DO NOTHING; LOAD PGSQL SERVERS TO RUNTIME; SAVE PGSQL SERVERS TO DISK;\"" 2>/dev/null && {
    log_success "  Added to proxysql-2 instance 2"
} || {
    log_warn "  Failed to add to proxysql-2 instance 2 (check if already exists or add manually)"
}

cd "$PROJECT_DIR"
log_success ""
log_success "=== Node $NODE_NAME added successfully! ==="
log_info ""
log_info "Node details:"
log_info "  Name: $NODE_NAME"
log_info "  ID: $NODE_NUM"
log_info "  Directory: $NODE_DIR"
log_info ""
log_info "Next steps:"
log_info "1. Wait 30-60 seconds for $NODE_NAME to initialize"
log_info "2. Check deployment: railway logs --service $NODE_NAME"
log_info "3. Verify cluster status:"
log_info "   railway ssh --service pg-1"
log_info "   gosu postgres repmgr -f /etc/repmgr/repmgr.conf cluster show"
log_info "4. Verify ProxySQL includes $NODE_NAME:"
log_info "   railway service proxysql"
log_info "   railway run bash -c \"PGPASSWORD=admin psql -h 127.0.0.1 -p 6132 -U admin -d proxysql -c 'SELECT * FROM pgsql_servers;'\""
log_info ""
log_info "To add another node: $0 $((NODE_NUM + 1))"
