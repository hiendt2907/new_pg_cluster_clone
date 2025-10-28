#!/bin/bash
# Generate secure random passwords for PostgreSQL HA Cluster
# Usage: ./scripts/generate-passwords.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"
ENV_EXAMPLE="$PROJECT_DIR/.env.example"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     PostgreSQL HA Cluster - Secure Password Generator       ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to generate secure password (32 chars, alphanumeric + safe symbols)
generate_password() {
    # Use alphanumeric only to avoid sed/shell escaping issues
    LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32
}

# Check if .env already exists
if [ -f "$ENV_FILE" ]; then
    echo -e "${YELLOW}⚠️  Warning: .env file already exists!${NC}"
    echo ""
    echo "Existing passwords will be backed up to: .env.backup"
    echo ""
    read -p "Do you want to regenerate all passwords? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}✅ Keeping existing .env file${NC}"
        echo ""
        echo "To view current credentials, run:"
        echo -e "  ${CYAN}./scripts/show-credentials.sh${NC}"
        exit 0
    fi
    echo ""
    echo -e "${BLUE}📦 Backing up existing .env...${NC}"
    cp "$ENV_FILE" "$ENV_FILE.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Generate all passwords
echo -e "${BLUE}🔐 Generating secure passwords...${NC}"
POSTGRES_PASSWORD=$(generate_password)
REPMGR_PASSWORD=$(generate_password)
APP_READWRITE_PASSWORD=$(generate_password)
APP_READONLY_PASSWORD=$(generate_password)
PCP_PASSWORD=$(generate_password)
MONITORING_PASSWORD=$(generate_password)

# Create .env file from template
if [ -f "$ENV_EXAMPLE" ]; then
    cp "$ENV_EXAMPLE" "$ENV_FILE"
else
    echo -e "${RED}❌ Error: .env.example not found!${NC}"
    exit 1
fi

# Replace placeholder passwords with generated ones
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${POSTGRES_PASSWORD}/" "$ENV_FILE"
    sed -i '' "s/^REPMGR_PASSWORD=.*/REPMGR_PASSWORD=${REPMGR_PASSWORD}/" "$ENV_FILE"
    sed -i '' "s/^APP_READWRITE_PASSWORD=.*/APP_READWRITE_PASSWORD=${APP_READWRITE_PASSWORD}/" "$ENV_FILE"
    sed -i '' "s/^APP_READONLY_PASSWORD=.*/APP_READONLY_PASSWORD=${APP_READONLY_PASSWORD}/" "$ENV_FILE"
    sed -i '' "s/^PCP_PASSWORD=.*/PCP_PASSWORD=${PCP_PASSWORD}/" "$ENV_FILE"
    sed -i '' "s/^MONITORING_PASSWORD=.*/MONITORING_PASSWORD=${MONITORING_PASSWORD}/" "$ENV_FILE"
else
    # Linux
    sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${POSTGRES_PASSWORD}/" "$ENV_FILE"
    sed -i "s/^REPMGR_PASSWORD=.*/REPMGR_PASSWORD=${REPMGR_PASSWORD}/" "$ENV_FILE"
    sed -i "s/^APP_READWRITE_PASSWORD=.*/APP_READWRITE_PASSWORD=${APP_READWRITE_PASSWORD}/" "$ENV_FILE"
    sed -i "s/^APP_READONLY_PASSWORD=.*/APP_READONLY_PASSWORD=${APP_READONLY_PASSWORD}/" "$ENV_FILE"
    sed -i "s/^PCP_PASSWORD=.*/PCP_PASSWORD=${PCP_PASSWORD}/" "$ENV_FILE"
    sed -i "s/^MONITORING_PASSWORD=.*/MONITORING_PASSWORD=${MONITORING_PASSWORD}/" "$ENV_FILE"
fi

# Make .env readable only by owner
chmod 600 "$ENV_FILE"

echo -e "${GREEN}✅ Passwords generated successfully!${NC}"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}📄 Configuration saved to:${NC} .env"
echo -e "${YELLOW}🔒 File permissions set to:${NC} 600 (owner read/write only)"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}Generated passwords:${NC}"
echo -e "  • POSTGRES_PASSWORD: ${GREEN}[32 characters]${NC}"
echo -e "  • REPMGR_PASSWORD: ${GREEN}[32 characters]${NC}"
echo -e "  • APP_READWRITE_PASSWORD: ${GREEN}[32 characters]${NC}"
echo -e "  • APP_READONLY_PASSWORD: ${GREEN}[32 characters]${NC}"
echo -e "  • PCP_PASSWORD: ${GREEN}[32 characters]${NC}"
echo -e "  • MONITORING_PASSWORD: ${GREEN}[32 characters]${NC}"
echo ""
echo -e "${YELLOW}⚠️  SECURITY REMINDERS:${NC}"
echo -e "  1. ${RED}NEVER${NC} commit .env to Git (it's in .gitignore)"
echo -e "  2. Keep .env file secure and private"
echo -e "  3. Share credentials only through secure channels"
echo -e "  4. Rotate passwords regularly in production"
echo ""
echo -e "${GREEN}📋 Next steps:${NC}"
echo ""
echo -e "  1. Review .env configuration (optional):"
echo -e "     ${CYAN}cat .env${NC}"
echo ""
echo -e "  2. Start the cluster:"
echo -e "     ${CYAN}docker-compose up -d${NC}"
echo ""
echo -e "  3. Wait for initialization (~60 seconds):"
echo -e "     ${CYAN}sleep 60${NC}"
echo ""
echo -e "  4. View connection credentials:"
echo -e "     ${CYAN}./scripts/show-credentials.sh${NC}"
echo ""
echo -e "  5. Test the cluster:"
echo -e "     ${CYAN}cd test-app && npm install && node test-trading-pgpool.js${NC}"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
