#!/bin/bash

# ============================================================================
# Stop Script - LGTM+ Monitoring Stack
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "============================================================================"
echo "🛑 Stopping LGTM+ Monitoring Stack"
echo "============================================================================"
echo ""

# Check if stack is running
if ! docker-compose ps | grep -q "Up"; then
    echo "⚠️  Stack is not running"
    docker-compose ps
    exit 0
fi

echo "Stopping all services..."
docker-compose stop

echo ""
echo "✅ All services stopped"
echo ""
echo "Options:"
echo "  - Start again:    ./start.sh"
echo "  - Remove volumes: docker-compose down -v  (⚠️  DELETES ALL DATA)"
echo "  - View logs:      docker-compose logs"
echo ""
