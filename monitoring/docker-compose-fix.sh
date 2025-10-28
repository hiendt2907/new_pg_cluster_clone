#!/bin/bash
# Backup original
cp docker-compose.yml docker-compose.yml.bak

# Remove version line
sed -i '/^version:/d' docker-compose.yml

# Add profile to proxysql_exporter to disable it
sed -i '/proxysql_exporter:/a\    profiles:\n      - with-proxysql' docker-compose.yml

echo "✅ Fixed docker-compose.yml:"
echo "   - Removed obsolete 'version' line"
echo "   - Disabled proxysql_exporter (no ProxySQL service yet)"
