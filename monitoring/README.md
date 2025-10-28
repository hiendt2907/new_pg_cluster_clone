# LGTM+ Stack - PostgreSQL HA Cluster Monitoring

Complete observability stack using **LGTM+** (Loki + Grafana + Tempo + Mimir + Prometheus) for PostgreSQL High Availability cluster monitoring.

## 📊 Stack Components

| Component | Purpose | Port | Storage |
|-----------|---------|------|---------|
| **Grafana** | Unified visualization & dashboards | 3000 | SQLite + dashboards |
| **Prometheus** | Short-term metrics (15 days) | 9090 | TSDB (5GB) |
| **Mimir** | Long-term metrics (90 days) | 9009 | Filesystem |
| **Loki** | Log aggregation (30 days) | 3100 | Filesystem |
| **Tempo** | Distributed tracing (48h) | 3200 | Filesystem |
| **Alertmanager** | Alert routing & notification | 9093 | Filesystem |
| **Promtail** | Log shipper | 9080 | N/A |

### Exporters

| Exporter | Monitors | Port |
|----------|----------|------|
| **postgres_exporter** | PostgreSQL metrics (pg-1 to pg-4) | 9187-9190 |
| **mysqld_exporter** | ProxySQL metrics | 9104 |
| **node_exporter** | System metrics (CPU, RAM, Disk) | 9100 |
| **cAdvisor** | Container metrics | 8080 |

## 🚀 Quick Start

### 1. Prerequisites

```bash
# Docker & Docker Compose
docker --version  # >= 24.0
docker-compose --version  # >= 2.20

# Running PostgreSQL HA cluster
docker network inspect pg_cluster  # Should exist
```

### 2. Environment Setup

```bash
# Copy environment template
cp .env.example .env

# Generate secure passwords
export POSTGRES_PASSWORD=$(openssl rand -base64 32)
export PROXYSQL_ADMIN_PASSWORD=$(openssl rand -base64 32)
export GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 32)
export POSTGRES_APP_READONLY_PASSWORD=$(openssl rand -base64 32)

# Save to .env
cat > .env <<EOF
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
PROXYSQL_ADMIN_PASSWORD=${PROXYSQL_ADMIN_PASSWORD}
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
POSTGRES_APP_READONLY_PASSWORD=${POSTGRES_APP_READONLY_PASSWORD}
EOF

echo "✅ Passwords generated and saved to .env"
```

### 3. Start Monitoring Stack

```bash
# Start all services
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f grafana
```

### 4. Access Dashboards

| Service | URL | Credentials |
|---------|-----|-------------|
| **Grafana** | http://localhost:3000 | admin / (from .env) |
| **Prometheus** | http://localhost:9090 | N/A |
| **Alertmanager** | http://localhost:9093 | N/A |
| **Mimir** | http://localhost:9009 | N/A |
| **Loki** | http://localhost:3100 | N/A |
| **Tempo** | http://localhost:3200 | N/A |

## 📈 Dashboards

### Pre-configured Dashboards

1. **PostgreSQL Overview**
   - Cluster health & topology
   - Replication lag & status
   - Connection pool stats
   - Query performance (TPS, latency)

2. **PostgreSQL Performance**
   - Cache hit ratio
   - Slow queries (top 20)
   - Index usage
   - Table bloat
   - Lock contention

3. **PostgreSQL Replication**
   - Primary/standby status
   - Replication lag (seconds & bytes)
   - WAL shipping rate
   - Slot activity

4. **ProxySQL**
   - Connection pool usage
   - Query routing (read/write split)
   - Backend server health
   - Query latency (P50, P95, P99)

5. **System Resources**
   - CPU, Memory, Disk usage
   - Network I/O
   - Disk I/O & latency
   - Container metrics

6. **Logs Explorer**
   - PostgreSQL error logs
   - ProxySQL query logs
   - System logs
   - Monitoring stack logs

### Import Dashboards

```bash
# PostgreSQL overview (community dashboard)
# Go to Grafana → Dashboards → Import → ID: 9628

# Node exporter (system metrics)
# Import ID: 1860

# ProxySQL monitoring
# Import ID: 12859
```

## 🚨 Alerting

### Alert Categories

#### Critical Alerts (immediate action)
- PostgreSQL instance down
- No replicas connected
- Disk >95% full
- Max connections reached
- Replication lag >60 seconds

#### Warning Alerts (action within hours)
- High CPU/Memory usage (>80%)
- Replication lag >10 seconds
- Slow queries (>30 seconds)
- Cache hit ratio <80%
- Disk >80% full

### Alert Channels

Configure in `config/alertmanager.yml`:

```yaml
receivers:
  - name: 'critical'
    email_configs:
      - to: 'oncall@company.com'
    slack_configs:
      - channel: '#alerts-critical'
        webhook_url: 'https://hooks.slack.com/...'
    pagerduty_configs:
      - service_key: 'YOUR_KEY'
```

### Test Alerts

```bash
# Trigger test alert
curl -X POST http://localhost:9093/api/v1/alerts \
  -H 'Content-Type: application/json' \
  -d '[{
    "labels": {
      "alertname": "TestAlert",
      "severity": "warning"
    },
    "annotations": {
      "summary": "Test alert from monitoring stack"
    }
  }]'

# Check Alertmanager UI
open http://localhost:9093
```

## 📊 Metrics Reference

### PostgreSQL Metrics

```promql
# Connection count
pg_stat_activity_count

# Replication lag (seconds)
pg_replication_lag{application_name="repmgr"}

# Cache hit ratio
pg_cache_hit_ratio

# Transaction rate
rate(pg_stat_database_xact_commit[5m])

# Slow query count
pg_stat_activity_max_tx_duration > 30

# Table bloat
pg_stat_user_tables_n_dead_tup / pg_stat_user_tables_n_live_tup
```

### ProxySQL Metrics

```promql
# Client connections
mysql_global_status_client_connections_connected

# Backend server status
mysql_global_status_proxysql_backend_servers_status

# Query latency
mysql_global_status_queries_latency_p99

# Connection errors
rate(mysql_global_status_connection_errors[5m])
```

### System Metrics

```promql
# CPU usage
100 - (avg(irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Disk usage
(1 - (node_filesystem_avail_bytes / node_filesystem_size_bytes)) * 100

# Disk I/O
rate(node_disk_io_time_seconds_total[5m])
```

## 🔍 Log Queries (LogQL)

### PostgreSQL Logs

```logql
# Error logs
{job="postgresql"} |= "ERROR"

# Slow queries (>1000ms)
{job="postgresql"} |~ "duration: [0-9]{4,}\\.[0-9]+ ms"

# Connection attempts
{job="postgresql"} |= "connection"

# Replication errors
{job="postgresql",instance="pg-2"} |= "replication" |= "error"
```

### ProxySQL Logs

```logql
# Backend connection errors
{job="proxysql"} |= "backend" |= "error"

# Query routing
{job="proxysql"} |= "hostgroup"

# Client disconnections
{job="proxysql"} |= "disconnecting"
```

## 🛠️ Troubleshooting

### No Metrics in Grafana

```bash
# Check Prometheus targets
curl http://localhost:9090/api/v1/targets

# Check exporter health
curl http://localhost:9187/metrics  # postgres_exporter
curl http://localhost:9100/metrics  # node_exporter

# Check Prometheus scrapes
docker-compose logs prometheus | grep "error"
```

### Exporter Connection Refused

```bash
# Verify PostgreSQL network
docker network inspect pg_cluster

# Test database connection
docker exec -it postgres_exporter_pg1 sh
psql "postgresql://postgres:PASSWORD@pg-1:5432/postgres" -c "SELECT 1"

# Check exporter logs
docker-compose logs postgres_exporter_pg1
```

### High Memory Usage

```bash
# Check Prometheus retention
docker exec prometheus prometheus --query.max-samples=50000000

# Reduce retention in docker-compose.yml
# --storage.tsdb.retention.time=7d (instead of 15d)

# Restart Prometheus
docker-compose restart prometheus
```

### Loki Out of Disk Space

```bash
# Check Loki disk usage
du -sh /var/lib/docker/volumes/monitoring_loki_data

# Reduce retention in config/loki.yaml
# retention_period: 7d (instead of 30d)

# Compact old data
docker-compose restart loki
```

## 📦 Backup & Restore

### Backup Grafana Dashboards

```bash
# Export all dashboards
./scripts/backup-grafana.sh

# Backup to file
docker exec grafana grafana-cli admin export-dashboard \
  --output=/tmp/dashboards.json

docker cp grafana:/tmp/dashboards.json ./backups/
```

### Backup Prometheus Data

```bash
# Snapshot Prometheus TSDB
docker exec prometheus promtool tsdb create-blocks-from snapshot \
  --snapshot=/prometheus/snapshots/latest

# Copy snapshot
docker cp prometheus:/prometheus/snapshots ./backups/
```

### Restore from Backup

```bash
# Stop stack
docker-compose down

# Restore volumes
docker run --rm -v monitoring_grafana_data:/data \
  -v $(pwd)/backups:/backup alpine \
  sh -c "cd /data && tar xzf /backup/grafana.tar.gz"

# Start stack
docker-compose up -d
```

## 🔒 Security Hardening

### Change Default Passwords

```bash
# Grafana admin password
docker exec -it grafana grafana-cli admin reset-admin-password NEW_PASSWORD

# Alertmanager (edit config/alertmanager.yml)
# Add basic auth or use reverse proxy
```

### Enable HTTPS (with Nginx reverse proxy)

```nginx
server {
    listen 443 ssl http2;
    server_name grafana.example.com;
    
    ssl_certificate /etc/ssl/certs/grafana.crt;
    ssl_certificate_key /etc/ssl/private/grafana.key;
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### Restrict Network Access

```yaml
# docker-compose.yml
services:
  prometheus:
    networks:
      - monitoring  # Remove pg_cluster if not needed
    # Don't expose port publicly
    # ports:
    #   - "9090:9090"
```

## 📚 Resources

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/)
- [Tempo Documentation](https://grafana.com/docs/tempo/)
- [Mimir Documentation](https://grafana.com/docs/mimir/)
- [PostgreSQL Exporter](https://github.com/prometheus-community/postgres_exporter)

## 🤝 Contributing

1. Add new alert rules to `config/alerts/*.yml`
2. Create custom dashboards in Grafana
3. Export dashboards to `config/grafana/dashboards/`
4. Submit PR with changes

## 📝 License

MIT License - see LICENSE file

---

**Monitoring Stack Version:** 1.0.0  
**Last Updated:** October 27, 2025  
**Maintained by:** PostgreSQL HA Cluster Team
