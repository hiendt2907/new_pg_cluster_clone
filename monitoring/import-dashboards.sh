#!/bin/bash

GRAFANA_URL="http://localhost:3000"
GRAFANA_USER="admin"
GRAFANA_PASSWORD="5QBgYw9LRxZterRN1d3MRUNvUKnAltaHo9LH5c5F6Uc="

echo "🔄 Importing Grafana Dashboards..."
echo ""

# Function to import dashboard from grafana.com
import_dashboard() {
    local dashboard_id=$1
    local dashboard_name=$2
    
    echo "📊 Importing: $dashboard_name (ID: $dashboard_id)"
    
    # Download dashboard JSON
    dashboard_json=$(curl -s "https://grafana.com/api/dashboards/${dashboard_id}/revisions/latest/download")
    
    # Create import payload
    import_payload=$(cat <<EOF
{
  "dashboard": ${dashboard_json},
  "overwrite": true,
  "inputs": [
    {
      "name": "DS_PROMETHEUS",
      "type": "datasource",
      "pluginId": "prometheus",
      "value": "Prometheus"
    }
  ]
}
EOF
)
    
    # Import to Grafana
    result=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
        -d "${import_payload}" \
        "${GRAFANA_URL}/api/dashboards/import")
    
    if echo "$result" | grep -q "success\|imported"; then
        echo "   ✅ Success: $dashboard_name"
    else
        echo "   ⚠️  Check: $dashboard_name"
        echo "   Response: $(echo $result | jq -r '.message // .status')"
    fi
    echo ""
}

# Import dashboards
import_dashboard "9628" "PostgreSQL Database"
import_dashboard "1860" "Node Exporter Full"
import_dashboard "14282" "cAdvisor"
import_dashboard "11074" "Node Exporter for Prometheus Dashboard"

echo "✅ Dashboard import complete!"
echo ""
echo "🌐 Access Grafana: http://localhost:3000"
echo "   Username: admin"
echo "   Password: ${GRAFANA_PASSWORD}"
