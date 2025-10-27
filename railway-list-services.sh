#!/usr/bin/env bash
# railway-list-services.sh - List all services and volumes in project
set -euo pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }

log_info "Fetching Railway project info..."
echo ""

# Get project info
PROJECT_JSON=$(railway status --json 2>/dev/null)

# Parse project name
PROJECT_NAME=$(echo "$PROJECT_JSON" | python3 -c "import json, sys; print(json.load(sys.stdin).get('name', 'Unknown'))" 2>/dev/null || echo "Unknown")
log_info "Project: $PROJECT_NAME"
echo ""

# List services
log_info "Services:"
echo "$PROJECT_JSON" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    services = data.get('services', {}).get('edges', [])
    if not services:
        print('  No services found')
    else:
        for svc in services:
            name = svc['node']['name']
            svc_id = svc['node']['id']
            print(f'  • {name} (ID: {svc_id[:8]}...)')
except Exception as e:
    print(f'  Error: {e}')
"
echo ""

# List volumes
log_info "Volumes:"
echo "$PROJECT_JSON" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    volumes = data.get('volumes', {}).get('edges', [])
    if not volumes:
        print('  No volumes found')
    else:
        for vol in volumes:
            name = vol['node']['name']
            vol_id = vol['node']['id']
            mount = vol['node'].get('mountPath', 'N/A')
            print(f'  • {name} → {mount} (ID: {vol_id[:8]}...)')
except Exception as e:
    print(f'  Error: {e}')
"
echo ""

log_info "To delete services, use:"
echo "  ./railway-cleanup.sh pg-1 pg-2 ..."
echo "  or manually via: railway open"
